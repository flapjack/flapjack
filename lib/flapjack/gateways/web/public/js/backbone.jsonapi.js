
var toolbox = {};

// toolbox.findById = function (array, id) {
//   return _.find(array, function (item) {
//     return item.id === id;
//   });
// };

toolbox.getMainCollection = function (response) {
  return _.without(_.keys(response), 'links', 'linked', 'meta')[0];
};

toolbox.batchRequest = function(klass, ids, amount, success) {
  // batch requests to avoid GET length limits
  var grouped = _.groupBy(ids, function(element, index){
    return Math.floor(index/75);
  });

  _.each(grouped, function(ids, index) {
    var linkedClass = klass.extend({
      url: function() { return(klass.prototype.url.call() + "/" + ids.join(',')); }
    });
    var linkedCollection = new linkedClass();
    linkedCollection.fetch({'reset' : true, 'success' : success});
  });
}

Backbone.Model.prototype.resolveLink = function(name, klass, superset) {
  if ( !_.isUndefined(this.get('links')) && !_.isUndefined(this.get('links')[name]) ) {
    context = this;
    var records = superset.filter(function(obj) {
      return(context.get('links')[name].indexOf(obj.get('id')) > -1);
    });
    if ( _.isUndefined(this.get('linked')) ) {
      this.set('linked', {});
    }
    if ( _.isUndefined(this.get('linked')[name]) ) {
      this.get('linked')[name] = new klass();
    }
    this.get('linked')[name].add(records);
  }
}

Backbone.Model.prototype.resolveLinks = function(name_klass_h) {
  if ( _.isUndefined(this.linked) ) {
    this.linked = {};
  }

  var context = this;

 _.each(name_klass_h, function(klass, name) {

    if ( !_.isUndefined(context.links[name]) && !_.isEmpty(context.links[name]) ) {
      context.linked[name] = new klass();

      var success = function(resultCollection, response, options) {
        context.resolveLink(name, klass, resultCollection);
      }

      toolbox.batchRequest(klass, context.links[name], 75, success);
    }
  });
}

Backbone.Collection.prototype.resolveLinks = function(name_klass_h) {
  if ( _.isUndefined(this.linked) ) {
    this.linked = {};
  }

  var context = this;

  _.each(name_klass_h, function(klass, name) {

    if ( !_.isUndefined(context.links[name]) && !_.isEmpty(context.links[name]) ) {
      context.linked[name] = new klass();

      var success = function(resultCollection, response, options) {
        context.forEach(function(obj, index) {
          obj.resolveLink(name, klass, resultCollection);
        });
      }

      toolbox.batchRequest(klass, context.links[name], 75, success);
    }
  });
};

Backbone.Collection.prototype.parse = function (response) {
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
};

Backbone.Model.prototype.parse = function (response) {
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
};

toolbox.savePatch = function(model, attrs, patch) {
  var patch_json = JSON.stringify(patch);
  return model.save(attrs, {
    data: patch_json,
    patch: true,
    contentType: 'application/json-patch+json'
  });
};

// makes sense to call this with model.patch(model.changedAttributes),
// if that value isn't false
Backbone.Model.prototype.patch = function(attrs) {
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
      path: '/' + context.urlType + '/0/' + key,
      value: val
    });

    return memo;
  }, new Array());

  toolbox.savePatch(this, attrs, patch);
};

// singular operation only -- TODO batch up and submit en masse
Backbone.Model.prototype.addLinked = function(urlType, type, obj) {
  var patch = [{
    op: 'add',
    path: '/' + urlType + '/0/links/' + type + '/-',
    value: obj.get('id')
  }];

  toolbox.savePatch(this, {}, patch);
  this.get('linked')[type].add(obj);
};

// singular operation only -- TODO batch up and submit en masse
Backbone.Model.prototype.removeLinked = function(urlType, type, obj) {
  var patch = [{
    op: 'remove',
    path: '/' + urlType + '/0/links/' + type + '/' + obj.get('id'),
  }];

  toolbox.savePatch(this, {}, patch);
  this.get('linked')[type].remove(obj);
};
