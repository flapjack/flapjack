
$( document ).ready(function() {

var app = {}; // namespace

  _.templateSettings = {
      interpolate: /<@=(.+?)@>/g,
      escape: /<@-(.+?)@>/g,
      evaluate: /<@(.+?)@>/g
  };

  app.Contact = Backbone.Model.extend({

    defaults: {
      id: null,
      first_name: '',
      last_name: '',
      email: ''
    },

    name: 'contacts',

    toJSON: function() {
      return { contacts: [ _.clone( this.attributes ) ] }
    }

  });

  app.ContactCollection = Backbone.Collection.extend({
    model: app.Contact,

    // to be swapped out for remote storage when API is ready
    // localStorage: new Backbone.LocalStorage("ContactCollection")

    // use current API host/port when served by Sinatra
    url: 'http://localhost:5081/contacts'
  });

  app.ActionsView = Backbone.View.extend({

    tagName: 'div',
    className: 'actions',

    template: _.template($('#contact-actions-template').html()),

    events: {
      "click .contact_add" : "add",
    },

    add: function() {
      // NB: requires numeric ids
      //var latest = this.collection.max(function(contact) {
      //  return contact.get('id');
      //});
      //var new_id = (latest <= 0) ? 1 : (latest.get('id') + 1);
      //var contact = new app.Contact({id: new_id});
      var contact = new app.Contact();
      this.collection.add(contact);
    },

    render: function() {
      this.$el.html(this.template({}));
      return this;
    }

  });

  app.ContactList = Backbone.View.extend({

    tagName: 'ul',
    className: 'contactList',

    template: _.template($('#contact-list-item-template').html()),

    initialize: function() {
      this.collection.on('add', this.render, this);
    },

    render: function() {
      var jqel = $(this.el);

      jqel.find('li').remove();

      this.collection.each(function(contact) {
        var item = new app.ContactListItem({ model: contact });
        jqel.append(item.render().el);
      });

      return this;
    },


  });

  app.ContactListItem = Backbone.View.extend({
    tagName: 'li',

    template: _.template($('#contact-list-item-template').html()),

    events: {
      "click .contact_list_item" : "toggle",
      "click .contact_save"      : "save",
      "click .contact_reset"     : "reset",
      "click .contact_remove"    : "remove",
    },

    render: function() {
      var template_values = _.clone(this.model.attributes);

      var display = this.$el.children('.contact').css('display');
      if ( _.isUndefined(display) || (display == 'none') ) {
        display = 'none';
      } else {
        display = 'block';
      }
      template_values['display'] = display;

      this.$el.html(this.template(template_values));
      return this;
    },

    toggle: function() {
      this.$el.children('.contact').toggle();
    },

    save: function() {
      this.model.save({
        first_name: this.$el.find('input.contact_first_name').val(),
        last_name:  this.$el.find('input.contact_last_name').val(),
        email:      this.$el.find('input.contact_email').val()
      });
      this.$el.children('.contact').hide();
      this.render();
    },

    reset: function() {
      this.render();
    },

    remove: function() {
      this.model.destroy();
      this.$el.remove();
    }

  });

  // uses underscored fields as that's what the API will serve back
  //var contact = new app.Contact({'first_name' : 'Abcdef',
  //                               'last_name' : 'Ghijklmnop',
  //                               'email' : 'abcdef.g@example.com'});

  var contacts = new app.ContactCollection();
  contacts.fetch();
  //contacts.add(contact);
  var actionsView = new app.ActionsView({collection: contacts});
  var contactList = new app.ContactList({collection: contacts});
  $('#container').append(actionsView.render().el);
  $('#container').append(contactList.render().el);
});
