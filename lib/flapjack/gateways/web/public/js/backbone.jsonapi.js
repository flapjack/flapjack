
var toolbox = {};

toolbox.getMainCollection = function (response) {
  return _.without(_.keys(response), 'links', 'linked', 'meta')[0];
};

// from http://stackoverflow.com/questions/105034/how-to-create-a-guid-uuid-in-javascript
toolbox.generateUUID = function() {
  var d = new Date().getTime();
  var uuid = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
    var r = (d + Math.random()*16)%16 | 0;
    d = Math.floor(d/16);
    return (c=='x' ? r : (r&0x7|0x8)).toString(16);
  });
  return uuid;
};

toolbox.batchRequest = function(klass, ids, amount, success) {
  // batch requests to avoid GET length limits
  var grouped;

  var batch_size = 75;

  if (ids.length <= batch_size) {
    grouped = _.groupBy(ids, function(element, index){
      return Math.floor(index/batch_size);
    });
  } else {
    grouped = {1: ids};
  }

  return( _.map(grouped, function(id_group, index) {
    var linkedClass = klass;

    if (id_group.length > 0) {
      linkedClass = linkedClass.extend({
        url: function() { return(klass.prototype.url.call() + "/" + id_group.join(',')); }
      });
    }

    var linkedCollection = new linkedClass();
    return linkedCollection.fetch({'reset' : true, 'success' : success});
  }));
};

Backbone.JSONAPIModel = Backbone.Model.extend({

  // the following two methods, and batchRequest, should be folded into
  // Collection.fetch (and Model.fetch?)
  resolveLink: function(name, klass, superset) {
    if ( _.isUndefined(this.get('links')[name]) ) {
      this.linked[name] = new klass();
    } else {
      context = this;
      var records = superset.filter(function(obj) {
        return(context.get('links')[name].indexOf(obj.get('id')) > -1);
      });
      if ( _.isUndefined(this.linked[name]) ) {
        this.linked[name] = new klass();
      }
      this.linked[name].add(records);
    }
  },

  resolveLinks: function(name_klass_h) {
    var context = this;

    return _.flatten( _.map(name_klass_h, function(klass, name) {
      if ( _.isUndefined(context.linked) ) {
        context.linked = {};
      }

      var links_name = context.get('links')[name];
      if ( !_.isUndefined(links_name) && !_.isEmpty(links_name) ) {

        var success = function(resultCollection, response, options) {
          context.resolveLink(name, klass, resultCollection);
        };

        return toolbox.batchRequest(klass, links_name, 75, success);
      } else {
        return($.when(context.resolveLink(name, klass, new Array())));
      }
    }));
  },

  parse: function (response) {
    if (response === undefined) {
      return;
    }
    if (response._alreadyBBJSONAPIParsed) {
      delete response._alreadyBBJSONAPIParsed;
      return response;
    }
    var mainCollection = toolbox.getMainCollection(response);
    var obj = response[mainCollection][0];

    return obj;
  },

  // post: function(urlType, attrs, options) {
  //   if ( _.isUndefined(options) || _.isNull(options) ) {
  //     options = {};
  //   }

  //   postData = {}
  //   postData[urlType] = [attrs];

  //   return(this.save({}, _.extend(options, {
  //     contentType: 'application/vnd.api+json',
  //     data: JSON.stringify(postData)
  //   })));
  // },

  // NB: should not be exported
  savePatch: function(attrs, patch, options) {
    if ( _.isUndefined(options) || _.isNull(options) ) {
      options = {};
    }
    return(this.save(attrs, _.extend(options, {
      data: JSON.stringify(patch),
      patch: true,
      contentType: 'application/json-patch+json'
    })));
  },

  patch: function(urlType, attrs, options) {
    if (attrs == null) {
      attrs = {};
    }

    var context = this;

    var patch = _.inject(attrs, function(memo, val, key) {
      // skip if not a simple attribute value
      if ( (key == 'links') || _.isObject(val) || _.isArray(val) ) {
        return memo;
      }

      memo.push({
        op: 'replace',
        path: '/' + urlType + '/0/' + key,
        value: val
      });

      return memo;
    }, new Array());

    this.savePatch(attrs, patch, options);
  },

  // singular operation only -- TODO batch up and submit en masse
  addLinked: function(urlType, type, obj, options) {
    var id = obj.get('id');

    var patch = [{
      op: 'add',
      path: '/' + urlType + '/0/links/' + type + '/-',
      value: id
    }];

    this.savePatch({}, patch, {}, options);

    if ( _.isUndefined(this.get('links')[type]) ) {
      this.get('links')[type] = new Array();
    }
    this.get('links')[type].push(id);
    this.linked[type].add(obj);
  },

  // singular operation only -- TODO batch up and submit en masse
  removeLinked: function(urlType, type, obj, options) {
    var id = obj.get('id');

    var patch = [{
      op: 'remove',
      path: '/' + urlType + '/0/links/' + type + '/' + id,
    }];

    this.savePatch({}, patch, {}, options);

    if ( _.isUndefined(this.get('links')[type]) ) {
      this.get('links')[type] = new Array();
    }
    this.get('links')[type] = _.without(this.get('links')[type], id);
    this.linked[type].remove(obj);
  },

  urlRoot: function() { return(flapjack.api_url + "/" + this.name); },

  // can only be called from inside a 'change' event
  setDirty: function() {
    if ( !this.hasChanged() ) {
      return;
    }

    this.dirty = true;
    if ( _.isUndefined(this.clean) ) {
      this.clean = {};
    }
    var context = this;

    // foreach changed attribute, merge previous value into a 'clean' hash
    // (only if the key isn't already in there)
    _.each(_.without(_.keys(this.changedAttributes()), _.keys(this.clean)), function(key) {
      context.clean[key] = context.previous(key);
    });
  },

  // can only be called from outside a change event
  revertClean: function() {
    if ( !_.isUndefined(this.clean) ) {
      this.set(this.clean, {silent: true});
    }
    this.clean = {};
    this.dirty = false;
  },

  sync: function(method, model, options) {
    if ( method == 'create' ) {
      // patch sets its own content type, get and delete don't have body content
      data                    = {};
      data[model.name]        = [options.attrs || model.toJSON(options)];
      options['data']         = JSON.stringify(data)
      options['contentType']  = 'application/vnd.api+json';
    }
    var succ = function(data, response, opts) {
      model.clean = {};
      model.dirty = false;
    };
    if ( _.isUndefined(options['success']) ) {
      options['success'] = succ;
    } else {
      options['success'] = [options['success'], succ];
    }

    Backbone.sync(method, model, options);
  }

});


Backbone.JSONAPICollection = Backbone.Collection.extend({

  resolveLinks: function(name_klass_h) {
    if ( _.isUndefined(this.linked) ) {
      this.linked = {};
    }

    var context = this;

    _.each(name_klass_h, function(klass, name) {

      if ( !_.isUndefined(context.links[name]) && !_.isEmpty(context.links[name]) ) {
        context.linked[name] = new klass();

        var success = function(resultCollection, response, options) {
          context.forEach(function(obj, index) {
            if ( _.isUndefined(obj.linked) ) {
              obj.linked = {};
            }
            obj.resolveLink(name, klass, resultCollection);
          });
        }

        toolbox.batchRequest(klass, context.links[name], 75, success);
      }
    });
  },

  parse: function (response) {
    if (response === undefined) {
      return;
    }

    this.links = {};
    var context = this;

    var mainCollection = toolbox.getMainCollection(response);
    var objects = _.map(response[mainCollection], function (obj) {
      _.each(obj.links, function(ids, name) {
        if ( _.isUndefined(context.links[name]) ) {
          context.links[name] = new Array();
        }
        if ( _.isArray(ids) ) {
          context.links[name] = context.links[name].concat(ids);
        }
      });

      obj._alreadyBBJSONAPIParsed = true;
      return obj;
    });

    this.links = _.reduce(this.links, function(memo, ids, name) {
      memo[name] = _.uniq(ids);
      return(memo);
    }, {});

    return objects;
  }

});
