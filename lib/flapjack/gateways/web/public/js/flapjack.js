
_.templateSettings = {
    interpolate: /<@=(.+?)@>/g,
    escape: /<@-(.+?)@>/g,
    evaluate: /<@(.+?)@>/g
};

var flapjack = {

  module: function() {
    // Internal module cache.
    var modules = {};

    // Create a new module reference scaffold or load an
    // existing module.
    return function(name) {
      // If this module has already been created, return it.
      if (modules[name]) {
        return modules[name];
      }

      // Create a module and save it under this name
      return modules[name] = { Views: {} };
    };
  }()
};

$(document).ready(function() {

  flapjack['api_url'] = $('div#data-api-url').data('api-url');

  var Contact = flapjack.module("contact");

  var contactList = new Contact.List();

  contactList.fetch({
    success: function(collection, response, options) {
      var contactListView = new (Contact.Views.List)({collection: collection});
      contactListView.render();
      $('#contactList').replaceWith(contactListView.$el);
    }
  });

});