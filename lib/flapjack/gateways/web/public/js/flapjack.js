
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

  flapjack.ActionsView = Backbone.View.extend({
    initialize: function() {
      this.template = _.template($('#contact-actions-template').html());
    },
    tagName: 'div',
    className: 'actions',
    events: {
      "click button#addContact" : "addContact",
    },
    render: function() {
      this.$el.html(this.template({}));
      return this;
    },
    addContact: function() {
      // skip if modal showing
      if ( $('#contactModal').hasClass('in') ) { return; }

      var contactView = new (Contact.Views.Contact)({model: new (Contact.Model)()});
      contactView.render();
    }
  });

  flapjack['api_url'] = $('div#data-api-url').data('api-url');

  var Contact = flapjack.module("contact");

  var actionsView = new flapjack.ActionsView();

  var contactList = new Contact.List();

  contactList.fetch({
    success: function(collection, response, options) {
      var contactListView = new (Contact.Views.List)({collection: collection});
      contactListView.render();
      $('tbody#contactList').replaceWith(contactListView.$el);

      $('tbody#contactList > tr > td').mouseenter(function(e) {
        e.stopPropagation();
        $(this).parent().find('td.actions button').css('visibility', 'visible');
      }).mouseleave(function(e) {
        e.stopPropagation();
        $(this).parent().find('td.actions button').css('visibility', 'hidden');
      });

      $('#contactModal').on('hidden.bs.modal', function (e) {
        e.stopImmediatePropagation();
        $('div.modal-dialog').empty();
      });

      $('#container').append(actionsView.render().el);
    }
  });

});