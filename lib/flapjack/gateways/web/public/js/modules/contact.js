(function(flapjack, Contact) {
  // Dependencies
  var Entity = flapjack.module("entity");
  var Medium = flapjack.module("medium");

  // Shorthands
  // The application container
  var app = flapjack.app;

  Contact.Model = Backbone.JSONAPIModel.extend({
    name: 'contacts',
    defaults: {
      first_name: '',
      last_name: '',
      email: '',
      id: null
    },

    toJSON: function() {
      // TODO ensure that attributes has nothing outside the above, except 'links'
      return _.pick(this.attributes, 'id', 'first_name', 'last_name', 'email');
    },

  });

  Contact.List = Backbone.JSONAPICollection.extend({
    model: Contact.Model,
    url: function() { return flapjack.api_url + "/contacts"; }
  });

  Contact.Views.Edit = Backbone.View.extend({
  });

  Contact.Views.ListItem = Backbone.View.extend({
    tagName: 'tr',
    className: 'contact_list_item',
    events: {
      'click .button.delete-contact': 'removeContact',
      'click':                        'editContact',
    },
    initialize: function() {
      this.template = _.template($('#contact-list-item-template').html());
      // // causes an unnecessary render on create, but required for update TODO cleanup
      // this.listenTo(this.model, "sync", this.render);
    },

    render: function() {
      var template_values = _.clone(this.model.attributes);
      this.$el.html(this.template(template_values));
      return this;
    },

    editContact: function() {

      // skip if modal showing
      if ( $('#contactModal').hasClass('in') ) { return; }

      var newContact = this.model.isNew();

      $('#contactModal h4#contactModalLabel').text(newContact ? 'New Contact' : 'Edit Contact');
      $('#contactModal button#contactAccept').text(newContact ? 'Create Contact' : 'Update Contact');

      $('#contactModal button#contactAccept').click(function() {
        // TODO disable button, re-enable after success/failure
        context.save();
      });

      var contactDetailsForm = new Contact.Views.DetailsForm({model: this.model});
      $('#contactModal div#contactDetails').replaceWith(contactDetailsForm.render().$el);

      var deferreds = this.model.resolveLinks({entities: Entity.List,
                                               media:    Medium.List});

      var allEntities = new Entity.List();

      deferreds.push(allEntities.fetch());

      var context = this;

      $.when.apply($, deferreds).done(
        function() {
          var entities = context.model.linked['entities'];
          var media    = context.model.linked['media'];

          var entityList = new Contact.Views.EntityList({collection: entities, contact: context.model});
          $('#contactModal tbody#contactEntityList').replaceWith( entityList.render().$el );

          var entityChooser = new Contact.Views.EntityChooser({contact: context.model, current: entities, all: allEntities});
          $('#contactModal div#contactEntityChooser').replaceWith( entityChooser.render().$el )

          var mediaList = new Contact.Views.MediaList({collection: media, contact: context.model});
          $('#contactModal tbody#contactMediaList').replaceWith( mediaList.render().$el );

        });

      $('#contactModal').modal('show');
    },

    removeContact: function(event) {
      event.stopImmediatePropagation();

      var context = this;

      this.model.destroy({
        success: function() {
          context.remove();
        }
      });
    }

  });

  Contact.Views.DetailsForm = Backbone.View.extend({
    initialize: function() {
      this.template = _.template($('#contact-template').html());
    },
    id: 'contactDetails',
    render: function() {
      var template_values = _.clone(this.model.attributes);
      this.$el.html(this.template(template_values));
      return this;
    }
  });

  Contact.Views.MediaListItem = Backbone.View.extend({
    tagName: 'tr',
    events: {
      // scoped to this view's el
      'change input' : 'updateMedium'
    },
    initialize: function() {
      this.template = _.template($('#contact-media-list-item-template').html());
    },
    render: function() {
      var template_values = _.clone(this.model.attributes);
      template_values['labels'] = {
        'email'  : 'Email',
        'sms'    : 'SMS',
        'jabber' : 'Jabber'
      };
      this.$el.html(this.template(template_values));
      return this;
    },
    updateMedium: function(event) {
      // var address =  $(event.target).parent('td')
      //                 .siblings().addBack().find('input[data-attr=address]');
      // var interval = $(event.target).parent('td')
      //                 .siblings().addBack().find('input[data-attr=interval]');
      // var rollupThreshold =
      //                $(event.target).parent('td')
      //                 .siblings().addBack().find('input[data-attr=rollup_threshold]');

      // var addressVal = address.val();
      // var intervalVal = interval.val();
      // var rollupThresholdVal = rollupThreshold.val();

      // var numRE = /^[0-9]+$/;

      // if ( !numRE.test(intervalVal) || !numRE.test(rollupThresholdVal) ) {
      //   // only save if numeric fields have acceptable values
      //   return;
      // }

      // if ( _.isUndefined(addressVal) || (addressVal.length == 0) ) {
      //   // only save if address not blank
      //   return;
      // }

      // // TODO visually highlight error

      // var attrName = event.target.getAttribute('data-attr');
      // var value = event.target.value;

      // var attrs = {};
      // attrs[attrName] = value;

      if ( this.model.isNew() ) {
        this.model.save(attrs);
        this.model.set('id', this.model.contact.get('id') + '_' + this.model.get('type'));
      } else {
        this.model.patch('media', attrs);
      }
    }
  });

  Contact.Views.MediaList = Backbone.View.extend({
    tagName: 'tbody',
    id: 'contactMediaList',
    initialize: function(options) {
      var context = this;

      _.each(['email', 'sms', 'jabber'], function(type) {
        var medium = context.collection.find(function(cm) {
          return cm.get('type') == type;
        });

        if ( _.isUndefined(medium) ) {
          medium = new Medium.Model({
            type: type,
            address: '',
            interval: 15,
            rollup_threshold: 3,
          });
          medium.contact = options.contact;
          context.collection.add(medium);
        }
      });
    },
    render: function() {
      var jqel = $(this.el);
      jqel.empty();

      this.collection.each(function(medium) {
        var item = new Contact.Views.MediaListItem({ model: medium });
        jqel.append(item.render().el);
      });

      return this;
    }
  });

  // this.model      == current contact
  // this.collection == duplicate of entities with
  //     entities enabled for this contact removed
  Contact.Views.EntityChooser = Backbone.View.extend({
    id: "contactEntityChooser",
    events: {
      'click button#add-contact-entity' : 'addEntities',
    },
    initialize: function(options) {
      this.options = options || {};
      this.template = _.template($('#contact-entity-chooser').html());
      this.listenTo(options.current, 'add',    this.refresh);
      this.listenTo(options.current, 'remove', this.refresh);
    },
    render: function() {

      this.calculate();

      // clear array
      this.entityIdsToAdd = new Array();

      this.$el.html(this.template({}));

      var jqel = $(this.el).find('input#entityChooser');

      var context = this;
      jqel.on('change', function(e) {
        if ( !_.isArray(e.removed) && _.isObject(e.removed) ) {
          context.entityIdsToAdd = _.without(context.entityIdsToAdd, e.removed.id);
        }

        if (  !_.isArray(e.added) && _.isObject(e.added) && (context.entityIdsToAdd.indexOf(e.added.id) == -1) ) {
          context.entityIdsToAdd.push(e.added.id);
        }
      });

      var format = function(item) { return item.name; }
      var context = this;

      jqel.select2({
        placeholder: "Select Entities",
        data: {results: context.results, text: 'name'},
        formatSelection: format,
        formatResult: format,
        multiple: true,
        width: 'off',
      });

      return this;
    },
    calculate: function() {
      var contact_entity_ids = this.options.current.pluck('id');

      var some = this.options.all.reject(function(item, context) {
        return _.contains(contact_entity_ids, item.get('id'));
      });

      this.collection = new Entity.List(some);

      this.results = this.collection.map( function(item) {
        return item.attributes;
      });
    },
    refresh: function(model, collection, options) {
      this.calculate();
      var jqel = $(this.el).find('input#entityChooser');
      var context = this;
      var format = function(item) { return item.name; }
      jqel.select2({
        placeholder: "Select Entities",
        data: {results: context.results, text: 'name'},
        formatSelection: format,
        formatResult: format,
        multiple: true,
        width: 'off',
      });
    },
    addEntities: function() {
      var jqel = $(this.el).find('input#entityChooser');
      jqel.select2("val", null);
      var context = this;
      _.each(this.entityIdsToAdd, function(entity_id) {
        var newEntity = context.options.all.find(function(entity) { return entity.id == entity_id; });
        context.options.contact.addLinked('contacts', 'entities', newEntity);
      });
      this.entityIdsToAdd.length = 0;
    }
  });

  Contact.Views.EntityListItem = Backbone.View.extend({
    tagName: 'tr',
    events: {
      'click button.delete-entity' : 'removeEntity',
    },
    initialize: function(options) {
      this.options = options || {};
      this.template = _.template($('#contact-entities-list-item-template').html());
    },
    render: function() {
      var template_values = _.clone(this.model.attributes);
      this.$el.html(this.template(template_values));
      return this;
    },
    removeEntity: function() {
      this.options.contact.removeLinked('contacts', 'entities', this.model);
      this.$el.remove();
    }
  });

  Contact.Views.EntityList = Backbone.View.extend({
    tagName: 'tbody',
    id: 'contactEntityList',
    initialize: function(options) {
      this.options = options || {};
      this.collection.on('add', this.render, this);
      this.collection.on('remove', this.render, this);
    },
    render: function() {
      var jqel = $(this.el);
      jqel.empty();
      var contact = this.options.contact;
      this.collection.each(function(entity) {
         var item = new Contact.Views.EntityListItem({ model: entity, contact: contact });
         jqel.append(item.render().el);
      });

      return this;
    }
  });

  Contact.Views.List = Backbone.View.extend({
    tagName: 'tbody',
    initialize: function() {
      this.collection.on('add', this.render, this);
    },
    render: function() {
      var jqel = this.$el;
      jqel.empty();
      this.collection.each(function(contact) {
        if ( !contact.isNew() ) {
          // won't render new contacts, but will add them to the list so
          // they can be edited and rendered properly once saved OK
          var item = new (Contact.Views.ListItem)({ model: contact });
          var itemEl = item.render().$el;
          jqel.append(itemEl);
        }
      });
      return this;
    }
  });

})(flapjack, flapjack.module("contact"));