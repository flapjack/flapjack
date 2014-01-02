
$( document ).ready(function() {

  var app = {}; // namespace

  _.templateSettings = {
      interpolate: /<@=(.+?)@>/g,
      escape: /<@-(.+?)@>/g,
      evaluate: /<@(.+?)@>/g
  };

  app.Entity = Backbone.Model.extend({

    name: 'entities',

    toJSON: function() {
      return { entities: [ _.clone( this.attributes ) ] }
    },

    urlRoot: $( "body" ).data("api-url" ) + "/entities"
  });

  app.EntityCollection = Backbone.Collection.extend({
    model: app.Entity,

    url: $( "body" ).data("api-url" ) + "/entities"
  });

  app.Contact = Backbone.Model.extend({

    name: 'contacts',

    toJSON: function() {
      return { contacts: [ _.clone( this.attributes ) ] }
    },

    // required for all linked data types received
    // TODO how will we handle circular references? make it a string and eval it?
    linkages: {
      entities: app.EntityCollection
    },

    urlRoot : $( "body" ).data("api-url" ) + "/contacts"
  });

  app.ContactCollection = Backbone.Collection.extend({
    model: app.Contact,
    url: $( "body" ).data("api-url" ) + "/contacts",
    linkages: {
      entities: app.EntityCollection
    },
  });

  app.ActionsView = Backbone.View.extend({

    tagName: 'div',
    className: 'actions',

    template: _.template($('#contact-actions-template').html()),

    events: {
      "click .contact_add" : "add",
    },

    add: function() {
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

  // var contact = new app.Contact({id: "4768"});
  // contact.fetch({success : function(model, response, options) {
  //   console.log(model.get('links')['entities']);
  // }});

  var contacts = new app.ContactCollection();
  contacts.fetch();

  // contacts.fetch({success : function(collection, response, options) {
  //   console.log(collection.at(0).get('links')['entities']);
  // }});

  var actionsView = new app.ActionsView({collection: contacts});
  var contactList = new app.ContactList({collection: contacts});
  $('#container').append(actionsView.render().el);
  $('#container').append(contactList.render().el);
});
