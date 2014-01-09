
var toolbox = {};

toolbox.findById = function (array, id) {
  return _.find(array, function (item) {
    return item.id === id;
  });
};

toolbox.resolveLinks = function(context, obj, linked) {
  if ( _.isUndefined(obj.links) ) { return; }

  _.each(obj.links, function(ids, name) {
    var linkage_type = context.linkages[name];

    if ( _.isUndefined(linkage_type) ) {
      obj.links[name] = null;
      return;
    }

    var linked_for_name = linked[name];

    if ( _.isUndefined(linked_for_name) ) {
      if ( _.isArray(ids) ) {
        obj.links[name] = new linkage_type();
      } else {
        obj.links[name] = null;
      }
      return;
    }

    if ( _.isArray(ids) ) {
      var collection = new linkage_type();
      collection.add(_.map(ids, function(id) {
        return new collection.model(toolbox.findById(linked_for_name, id));
      }));
      obj.links[name] = collection;
    } else {
      obj.links[name] = new linkage_type(toolbox.findById(linked_for_name, ids));
    }
  });

};

toolbox.getMainCollection = function (response) {
  return _.without(_.keys(response), 'links', 'linked', 'meta')[0];
};

Backbone.Collection.prototype.parse = function (response) {
  if (response === undefined) {
    return;
  }
  var mainCollection = toolbox.getMainCollection(response);
  var context = this;
  return _.map(response[mainCollection], function (obj) {
    toolbox.resolveLinks(context, obj, (response['linked'] || {}));
    obj._alreadyBBJSONAPIParsed = true;
    return obj;
  });
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
  toolbox.resolveLinks(this, obj, (response['linked'] || {}));
  return obj;
};

toolbox.savePatch = function(model, patch) {
  var patch_json = JSON.stringify(patch);
  return model.save({}, {
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
    if ( (key == links) || _.isObject(val) || _.isArray(val) ) {
      return memo;
    }

    memo.push({
      op: 'replace',
      path: '/' + context.urlType + '/0/' + key,
      value: val
    });

    return memo;
  }, new Array());

  toolbox.savePatch(this, patch);
};

// singular operation only -- TODO batch up and submit en masse
Backbone.Model.prototype.addLinked = function(type, obj) {
  var patch = [{
    op: 'add',
    path: '/' + this.urlType + '/0/links/' + type + '/-',
    value: obj.get('id')
  }];

  toolbox.savePatch(this, patch);
  this.get('links')[type].add(obj);
};

// singular operation only -- TODO batch up and submit en masse
Backbone.Model.prototype.removeLinked = function(type, obj) {
  var patch = [{
    op: 'remove',
    path: '/' + this.urlType + '/0/links/' + type + '/' + obj.get('id'),
  }];

  toolbox.savePatch(this, patch);
  this.get('links')[type].remove(obj);
};
