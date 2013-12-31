if (!Backbone || !_) {
  throw new Error('Backbone and/or Underscore are not loaded...');
}

// Underscore shim
_.forOwn = _.forOwn || function (obj, iterator) {
  var keys;
  try {
    keys = _.keys(obj);
  } catch (e) {
    return;
  }
  _.each(keys, function (key) {
    iterator(obj[key], key);
  });
};

var toolbox = {};

toolbox.findById = function (array, id) {
  return _.find(array, function (item) {
    return item.id === id;
  });
};

toolbox.applyTemplateUrl = function (collectionName, template, data) {
  var regex = new RegExp('{' + collectionName + '\\.(.+?)}', 'g'),
    execResult = regex.exec(template);
  if (execResult !== null) {
    if (data[execResult[1]] === undefined && data.links[execResult[1]] === undefined) {
      throw new Error('Template required a property not present in data object');
    }
    template = template.substr(0, execResult.index) + (data.links[execResult[1]] || data[execResult[1]]) + template.substr(regex.lastIndex);
  }
  return template;
};

toolbox.processLink = function (response, linkObj, linkName) {
  var linkNameSplit = linkName.split('.'),
    collection = linkNameSplit[0],
    attribute = linkNameSplit[1];

  _.each(response[collection], function (item) {
    item.links = item.links || {};
    if (item.links[attribute] !== undefined) {
      var preloadedItem = toolbox.findById(response[linkObj.type], item.links[attribute]);
      if (preloadedItem !== undefined) {
        item[attribute] = preloadedItem;
      }
    }
    try {
      item.links[attribute] = toolbox.applyTemplateUrl(collection, linkObj.href, item);
    } catch (e) {}
  });
  return response;
};

toolbox.parse = function (response) {
  _.forOwn(response.links, function (value, key) {
    toolbox.processLink(response, value, key);
  });
  return response;
};

toolbox.getMainCollection = function (response) {
  var collections = _.without(_.keys(response), 'links', 'meta');
  var types = _.pluck(_.values(response.links || []), 'type');
  return _.difference(collections, types)[0];
};

Backbone.Collection.prototype.parse = function (response) {
  if (response === undefined) {
    return;
  }
  var output = toolbox.parse(response);
  var mainCollection = toolbox.getMainCollection(response);
  console.log(mainCollection.length);
  return _.map(output[mainCollection], function (obj) {
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
  var output = toolbox.parse(response);
  var mainCollection = toolbox.getMainCollection(response);
  return output[mainCollection][0];
};
