$(document).ready(function() {

  // fix select2 with modal
  $.fn.modal.Constructor.prototype.enforceFocus = function() {};

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
    urlType: 'entities',
    urlRoot: function() { return app.api_url + "/" + this.urlType; }
  });

  app.EntityCollection = Backbone.Collection.extend({
    model:      app.Entity,
    comparator: 'name',
    urlType: 'entities',
    url: function() { return app.api_url + "/" + this.urlType; }
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
    urlType: 'contacts',
    urlRoot: function() { return app.api_url + "/" + this.urlType; }
  });

  app.ContactCollection = Backbone.Collection.extend({
    model: app.Contact,
    linkages: {
      entity: app.Entity,
      entities: app.EntityCollection
    },
    urlType: 'contacts',
    url: function() { return app.api_url + "/" + this.urlType; }
  });

  app.ActionsView = Backbone.View.extend({
    tagName: 'div',
    className: 'actions',
    template: _.template($('#contact-actions-template').html()),
    events: {
      "click button#addContact" : "addContact",
    },
    addContact: function() {
      // skip if modal showing
      if ( $('#contactModal').hasClass('in') ) { return; }

      $('#contactModal h4#contactModalLabel').text('New Contact');
      $('#contactModal button.btn.btn-success').text('Create Contact');

      var context = this;

      // TODO if validating or leaving modal open, re-establish the event
      $('#contactModal button.btn.btn-success').one('click', function() { context.save(); });

      this.model = new app.Contact();
      this.model.set('links', {entities: new app.EntityCollection()});

      var contactView = new app.ContactView({model: this.model});

      $('#contactModal div.modal-footer').siblings().remove();
      $('#contactModal div.modal-footer').before(contactView.render().$el);

      $('#contactModal tbody#contactEntityList').empty();

      var contactEntityList = new app.ContactEntityList({collection: this.model.get('links')['entities']});
      var entityChooser = new app.EntityChooser({model: this.model});

      $('#contactModal tbody#contactEntityList')
        .append( contactEntityList.render().$el )
        .append( entityChooser.$el );

      var contactMediaList = new app.ContactMediaList({collection: this.model.get('links')['entities']});

      $('#contactModal tbody#contactMediaList')
        .replaceWith( contactMediaList.render().$el )

      // after the element is attached to the DOM
      entityChooser.render();
      $('#add-contact-media').on('click', function() {
        var media = new app.Entity();
        contactMediaList.collection.add(media);
        contactMediaList.render().$el
      });

      $('#contactModal').modal('show');
    },
    render: function() {
      this.$el.html(this.template({}));
      return this;
    },
    save: function() {
      data = {'first_name': $('#contactModal input[name=contact_first_name]').val(),
              'last_name': $('#contactModal input[name=contact_last_name]').val(),
              'email': $('#contactModal input[name=contact_email]').val()};
      this.model.save(data, {type: 'POST', contentType: 'application/vnd.api+json'});
      contacts.add(this.model);
      $('#contactModal').modal('hide');
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

  app.ContactView = Backbone.View.extend({
    template: _.template($('#contact-template').html()),
    id: 'contactView',
    render: function() {
      var template_values = _.clone(this.model.attributes);
      this.$el.html(this.template(template_values));
      return this;
    }
  });

  app.ContactList = Backbone.View.extend({
    tagName: 'tbody',
    id: 'contactList',
    initialize: function() {
      this.collection.on('add', this.render, this);
    },
    render: function() {
      var jqel = $(this.el);
      jqel.empty();

      this.collection.each(function(contact) {
        var item = new app.ContactListItem({ model: contact });
        jqel.append($(item.render().el));
      });

      return this;
    },
  });

  app.ContactEntityList = Backbone.View.extend({
    tagName: 'tbody',
    id: 'contactEntityList',
    initialize: function() {
      this.collection.on('add', this.render, this);
    },
    render: function() {
      var jqel = $(this.el);
      jqel.empty();
      this.collection.each(function(entity) {
         var item = new app.ContactEntityListItem({ model: entity });
         jqel.append(item.render().el);
      });

      return this;
    },
  });

  app.ContactEntityListItem = Backbone.View.extend({
    tagName: 'tr',
    template: _.template($('#contact-entities-list-item-template').html()),
    events: {
      //'click .button.delete' : 'removeEntity',
    },
    render: function() {
      var template_values = _.clone(this.model.attributes);
      this.$el.html(this.template(template_values));
      return this;
    },
  });

  app.ContactListItem = Backbone.View.extend({
    tagName: 'tr',
    className: 'contact_list_item',
    template: _.template($('#contact-list-item-template').html()),
    events: {
      'click .button.delete': 'removeContact',
      'click':                'editContact',
    },
    initialize: function() {
      // causes an unnecessary render on create, but required for update TODO cleanup
      this.listenTo(this.model, "sync", this.render);
    },

    render: function() {
      var template_values = _.clone(this.model.attributes);
      this.$el.html(this.template(template_values));
      return this;
    },

    editContact: function() {
      // skip if modal showing
      if ( $('#contactModal').hasClass('in') ) { return; }

      $('#contactModal h4#contactModalLabel').text('Edit Contact');
      $('#contactModal button.btn.btn-success').text('Update Contact');

      var context = this;

      // TODO if validating or leaving modal open, re-establish the event
      $('#contactModal button.btn.btn-success').one('click', function() { context.save(); });

      var contactView = new app.ContactView({model: this.model});

      $('#contactModal div.modal-footer').siblings().remove();
      $('#contactModal div.modal-footer').before(contactView.render().$el);

      $('#contactModal tbody#contactEntityList').empty();

      var contactEntityList = new app.ContactEntityList({collection: this.model.get('links')['entities']});
      var entityChooser = new app.EntityChooser({model: this.model});

      $('#contactModal tbody#contactEntityList')
        .append( contactEntityList.render().$el )
        .append( entityChooser.$el );

      // after the element is attached to the DOM
      entityChooser.render();

      $('#contactModal').modal('show');
    },

    save: function() {
      data = {'first_name': $('#contactModal input[name=contact_first_name]').val(),
              'last_name': $('#contactModal input[name=contact_last_name]').val(),
              'email': $('#contactModal input[name=contact_email]').val()};
      this.model.save(data, {type: 'PUT', contentType: 'application/vnd.api+json'});
      $('#contactModal').modal('hide');
    },

    removeContact: function(e) {
      e.stopImmediatePropagation();

      var context = this;

      context.model.destroy({
        success: function() {
          context.remove()
        }
      });
    },
  });

  app.ContactMediaList = Backbone.View.extend({
    tagName: 'tbody',
    id: 'contactMediaList',
    initialize: function() {
      this.collection.on('add', this.render, this);
    },
    render: function() {
      var jqel = $(this.el);
      jqel.empty();
      this.collection.each(function(media) {
         var item = new app.ContactMediaListItem({ model: media });
         jqel.append(item.render().el);
      });

      return this;
    },
  });

  app.ContactMediaListItem = Backbone.View.extend({
    tagName: 'tr',
    template: _.template($('#contact-media-list-item-template').html()),
    events: {
      'click .button.delete': 'removeContactMedia',
    },
    render: function() {
      var template_values = _.clone(this.model.attributes);
      this.$el.html(this.template(template_values));
      return this;
    },
    removeContactMedia: function(e) {
      e.stopImmediatePropagation();
      var context = this;
      context.model.destroy({
        success: function() {
          context.remove()
        }
      });
    },
  });

  var allEntities = new app.EntityCollection();
  var contacts = new app.ContactCollection();

  allEntities.fetch({
    success: function(collection, response, options) {
      contacts.fetch({
        success: function(collection, response, options) {
          var actionsView = new app.ActionsView({collection: collection});
          var contactList = new app.ContactList({collection: collection});
          $('#container').append(actionsView.render().el);

          $('#contactList').replaceWith($(contactList.render().el));
        }
      });
    }
  });

});
