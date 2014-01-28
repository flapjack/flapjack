
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

