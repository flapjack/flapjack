$(document).ready(function() {

  var app = {
    api_url: $('div#data-api-url').data('api-url')
  };

  _.templateSettings = {
      interpolate: /<@=(.+?)@>/g,
      escape: /<@-(.+?)@>/g,
      evaluate: /<@(.+?)@>/g
  };

  app.Entity = Backbone.Model.extend({
    name: 'entities',
    defaults: {
      name: '',
      id: null
    },
    toJSON: function() {
      return { entities: [ _.clone( this.attributes ) ] }
    },
    urlRoot: app.api_url + "/entities"
  });

  app.EntityCollection = Backbone.Collection.extend({
    model: app.Entity,
    comparator: 'name',
    url: app.api_url + "/entities"
  });

  app.Contact = Backbone.Model.extend({
    name: 'contacts',
    defaults: {
      first_name: '',
      last_name: '',
      email: '',
      id: null
    },
    toJSON: function() {
      return { contacts: [ _.clone( this.attributes ) ] }
    },
    // required for all linked data types received
    // TODO how will we handle circular references? make it a string and eval it?
    linkages: {
      entity: app.Entity,
      entities: app.EntityCollection
    },
    urlRoot : app.api_url + "/contacts"
  });

  app.ContactCollection = Backbone.Collection.extend({
    model: app.Contact,
    url: app.api_url + "/contacts",
    linkages: {
      entity: app.Entity,
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
      contact.set('links', {entities: new app.EntityCollection()});
      this.collection.add(contact);
    },
    render: function() {
      this.$el.html(this.template({}));
      return this;
    }
  });


  // this.model      == current contact
  // this.collection == duplicate of entities with
  //     entities enabled for this contact removed
  app.EntityChooser = Backbone.View.extend({
    tagName: 'input',
    attributes: {type: 'hidden'},
    className: 'entityChooser',
    initialize: function() {
      var contact_entity_ids = this.model.get('links')['entities'].pluck('id');

      var someEntities = allEntities.reject(function(item, context) {
        return _.contains(contact_entity_ids, item.get('id'));
      });

      this.collection = new app.EntityCollection(someEntities);
    },
   render: function() {
      var jqel = $(this.el);

      var results = this.collection.map( function(item) {
        return item.attributes;
      });

      var format = function(item) { return item.name; }

      jqel.select2({
        placeholder: "Select an Entity",
        data: { results: results, text: 'name'},
        formatSelection: format,
        formatResult: format
      });

      return this;
    },

  });

  app.EntitiesEnabled = Backbone.View.extend({
    tagName: 'select',
    className: 'entityList',
    attributes: {
      size: "12",
      multiple: "multiple"
    },
    initialize: function() {
      this.collection.on('add', this.render, this);
    },
    render: function() {
      var jqel = $(this.el);

      jqel.find('option').remove();

      this.collection.each(function(entity) {
         var item = new app.EntityListItem({ model: entity });
         jqel.append(item.render().el);
      });

      return this;
    },
  });

  app.ContactList = Backbone.View.extend({
    tagName: 'ul',
    className: 'contactList',
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

  app.EntityListItem = Backbone.View.extend({
    tagName: 'option',
    render: function() {

      // TODO piggyback data from model record
      this.$el.html('<option>' + this.model.escape('name')  + '</option>');

      return this;
    }
  });

  app.ContactListItem = Backbone.View.extend({
    tagName: 'li',
    template: _.template($('#contact-list-item-template').html()),
    events: {
      "click button.contact_entities" : "toggleEntities",
      "click button.contact_edit"     : "toggleEdit",
      "click button.contact_save"     : "save",
      "click button.contact_reset"    : "reset",
      "click button.contact_remove"   : "remove",
    },

    render: function() {
      var template_values = _.clone(this.model.attributes);
      var el = this.$el;
      _.each(['entities', 'edit'], function(item) {
        var display = el.children('div.contact_' + item + '_view').css('display');

        if ( _.isUndefined(display) || (display == 'none') ) {
          display = 'none';
        } else {
          display = 'block';
        }
        template_values[item + '_display'] = display;
      });

      this.$el.html(this.template(template_values));

      var entities = this.model.get('links')['entities'];

      if ( _.isUndefined(entities) ) {
        entities = new app.EntityCollection();
      }

      var entitiesEnabled = new app.EntitiesEnabled({collection: entities});
      entitiesEnabled.render();

      var entityChooser = new app.EntityChooser({model: this.model});

      this.$el.find('div.contact_entities_view').empty()
        .append( entitiesEnabled.$el )
        .append( entityChooser.$el );

      // after the element is attached to the DOM
      entityChooser.render();

      return this;
    },
    toggleEntities: function() {
      this.$el.children('div.contact_entities_view').toggle();
    },
    toggleEdit: function() {
      this.$el.children('div.contact_edit_view').toggle();
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

  var allEntities = new app.EntityCollection();
  var contacts = new app.ContactCollection();

  allEntities.fetch({success: function(coll, response, options) {
    contacts.fetch({
      success: function(collection, response, options) {
        var actionsView = new app.ActionsView({collection: collection});
        var contactList = new app.ContactList({collection: collection});
          $('#container').append(actionsView.render().el);
          $('#container').append(contactList.render().el);
        }
    });
  }});

});
