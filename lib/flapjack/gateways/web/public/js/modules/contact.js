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
      id: null,
      links: {},
    },
    initialize: function(){
      Backbone.JSONAPIModel.prototype.initialize.apply(this, arguments);
      this.on('change', this.setDirty, this);
    },
    toJSON: function() {
      // TODO ensure that attributes has nothing outside the above, except 'links'
      return _.pick(this.attributes, 'id', 'first_name', 'last_name', 'email');
    },
    validate: function() {
      // TODO hack media-email-address edit to set contact.email field
      var fn = this.get('first_name');
      var ln = this.get('last_name');

      var errors = new Array();

      if ( _.isUndefined(fn) || _.isNull(fn) || (fn.length == 0) ) {
        errors.push("First name must be provided.");
      }

      if ( _.isUndefined(ln) || _.isNull(ln) || (ln.length == 0) ) {
        errors.push("Last name must be provided.");
      }

      if ( _.isEmpty(errors) ) {
        return;
      }

      return(errors);
    }
  });

  Contact.List = Backbone.JSONAPICollection.extend({
    model: Contact.Model,
    url: function() { return flapjack.api_url + "contacts"; }
  });

  Contact.Views.List = Backbone.View.extend({
    tagName: 'tbody',
    id: 'contactList',
    initialize: function() {
      this.collection.on('add', this.render, this);
      this.collection.on('remove', this.render, this);
    },
    render: function() {
      // TODO just rerender changed rows (insert new row or remove deleted)
      var jqel = this.$el;
      jqel.empty();

      this.collection.each(function(contact) {
        var item = new (Contact.Views.ListItem)({ model: contact });
        jqel.append(item.render().$el);
      });

      return this;
    }
  });

  Contact.Views.ListItem = Backbone.View.extend({
    tagName: 'tr',
    className: 'contact_list_item',
    events: {
      'click button.contact-media'    : 'editContactMedia',
      'click button.contact-entities' : 'editContactEntities',
      'click button.delete-contact'   : 'removeContact',
      'click td'                      : 'editContactDetails'
    },
    initialize: function() {
      this.template = _.template($('#contact-list-item-template').html());
      // causes an unnecessary render on create, but required for update TODO cleanup
      this.listenTo(this.model, "sync", this.render);
    },

    render: function() {
      var template_values = _.clone(this.model.attributes);
      this.$el.html(this.template(template_values));
      return this;
    },

    editContactDetails: function(e) {
      e.stopImmediatePropagation();
      // skip if modal showing
      if ( $('#contactModal').hasClass('in') ) { return; }

      var contactDetailsView = new Contact.Views.ContactDetails({model: this.model});
      contactDetailsView.render();

      $('div.modal-dialog').append(contactDetailsView.$el);
      $('#contactModal').modal('show');
    },

    editContactMedia: function(e) {
      e.stopImmediatePropagation();
      // skip if modal showing
      if ( $('#contactModal').hasClass('in') ) { return; }

      var context = this;

      var deferreds = this.model.resolveLinks({media: Medium.List});

      $.when.apply($, deferreds).done(
        function() {
          var media = context.model.linked['media'];

          var mediaMain = new Contact.Views.Media({collection: media, contact: context.model});
          $('div.modal-dialog').append(mediaMain.render().$el);

          $('#contactModal').on('hidden.bs.modal', function() {
            mediaMain.trigger('close');
          });

          $('#contactModal').modal('show');
        }
      );

    },

    editContactEntities: function(e) {
      e.stopImmediatePropagation();
      // skip if modal showing
      if ( $('#contactModal').hasClass('in') ) { return; }

      var deferreds = this.model.resolveLinks({entities: Entity.List});

      var allEntities = new Entity.List();

      deferreds.push(allEntities.fetch());

      var context = this.model;

      $.when.apply($, deferreds).done(
        function() {
          var entities = context.linked['entities'];

          var entitiesView = new Contact.Views.Entities({contact: context, current: entities, all: allEntities});
          $('div.modal-dialog').append(entitiesView.render().$el);

          $('#contactModal').modal('show');
        }
      );
    },

    removeContact: function(e) {
      e.stopImmediatePropagation();
      this.model.destroy();
    }

  });

  Contact.Views.ContactDetails = Backbone.View.extend({
    events: {
      "input input[name='contact_first_name'],input[name='contact_last_name']"  : 'updateAcceptButton',
      "change input[name='contact_first_name']" : 'setFirstName',
      "change input[name='contact_last_name']"  : 'setLastName',
      "click button#contactCancel" : 'cancel',
      "click button#contactAccept" : 'accept',
    },
    updateAcceptButton: function(event) {
      event.stopImmediatePropagation();

      var firstNameVal = $("input[name='contact_first_name']").val();
      var firstNameInvalid = _.isUndefined(firstNameVal) || _.isNull(firstNameVal) || _.isEmpty(firstNameVal);

      var lastNameVal = $("input[name='contact_last_name']").val();
      var lastNameInvalid = _.isUndefined(lastNameVal) || _.isNull(lastNameVal) || _.isEmpty(lastNameVal);

      $('button#contactAccept').prop('disabled', firstNameInvalid || lastNameInvalid);
    },
    setFirstName: function(event) {
      event.stopImmediatePropagation();
      this.model.set('first_name', $(event.target).val());
    },
    setLastName: function(event) {
      event.stopImmediatePropagation();
      this.model.set('last_name', $(event.target).val());
    },
    cancel: function(event) {
      event.stopImmediatePropagation();
      $('#contactModal').modal('hide');
      if ( this.model.dirty ) {
        this.model.revertClean();
      }
    },
    accept: function(event) {
      event.stopImmediatePropagation();

      $(event.target).prop('disabled', true);

      if ( this.model.isNew() ) {
        var save_success = function(model, response, options) {
          model.setPersisted(true);
          flapjack.contactList.add(model);
          $('#contactModal').modal('hide');
        };
        var save_error = function(model, response, options) {
        };

        this.model.save({}, {success: save_success, error: save_error});
      } else {

        if ( _.isUndefined(this.model.clean) ) {
          $('#contactModal').modal('hide');
        } else {
          var changedAttrKeys = _.keys(this.model.clean);
          if (changedAttrKeys.length > 0) {
            var save_success = function(data, response, options) {
              $('#contactModal').modal('hide');
            };
            var save_error = function(data, response, options) {
            };
            var attrs = _.pick(this.model.attributes, changedAttrKeys);
            this.model.patch('contacts', attrs, {success: save_success, error: save_error});
          } else {
            $('#contactModal').modal('hide');
          }
        }
      }

    },
    initialize: function() {
      this.template = _.template($('#contact-details-form-template').html());
    },
    render: function() {
      var template_values = _.clone(this.model.attributes);
      template_values['is_new'] = this.model.isNew();
      template_values['is_valid'] = this.model.isValid();

      this.$el.html(this.template(template_values));

      return this;
    }

  });

  Contact.Views.Media = Backbone.View.extend({
    initialize: function(options) {
      this.options = options || {};
      this.template = _.template($('#contact-media-template').html());
    },
    events: {
      'close' : 'revert',
    },
    revert: function() {
      if ( !_.isUndefined(this.mediaList) ) {
        this.mediaList.trigger('revert');
      }
    },
    render: function() {
      var template_values = _.clone(this.options.contact.attributes);
      this.$el.html(this.template(template_values));

      this.mediaList = new Contact.Views.MediaList({collection: this.options.collection, contact: this.options.contact});
      this.$el.find('tbody#contactMediaList').replaceWith(this.mediaList.render().$el);

      return this;
    }
  });

  Contact.Views.MediaList = Backbone.View.extend({
    tagName: 'tbody',
    id: 'contactMediaList',
    initialize: function(options) {
      var context = this;

      _.each(['email', 'sms', 'slack', 'sms_twilio', 'sms_nexmo', 'sns', 'jabber'], function(type) {
        var medium = context.collection.find(function(cm) {
          return cm.get('type') == type;
        });

        if ( _.isUndefined(medium) ) {
          medium = new Medium.Model({
            type: type,
            address: '',
            interval: 15,
            rollup_threshold: 3
          });
          medium.setPersisted(false);
          medium.set('id', options.contact.get('id') + '_' + type);
          context.collection.add(medium);
        }
        medium.contact = options.contact;
      });
    },
    events: {
      'revert' : 'revertUnsaved'
    },
    render: function() {
      var jqel = $(this.el);
      jqel.empty();

      this.collection.each(function(medium) {
        var item = new Contact.Views.MediaListItem({ model: medium });
        jqel.append(item.render().el);
      });

      return this;
    },
    revertUnsaved: function() {
      this.collection.each(function(medium) {
        medium.revertClean();
      });
    }
  });

  Contact.Views.MediaListItem = Backbone.View.extend({
    tagName: 'tr',
    events: {
      "change input[data-attr='address']"          : 'setAddress',
      "change input[data-attr='interval']"         : 'setInterval',
      "change input[data-attr='rollup_threshold']" : 'setRollupThreshold'
    },
    initialize: function() {
      this.template = _.template($('#contact-media-list-item-template').html());
    },
    render: function() {
      var template_values = _.clone(this.model.attributes);
      template_values['labels'] = {
        'email'      : 'Email',
        'sms'        : 'SMS (MessageNet)',
        'slack'      : 'Slack',
        'sms_twilio' : 'SMS (Twilio)',
        'sms_nexmo'  : 'SMS (Nexmo)',
        'sns'        : 'SMS (Amazon SNS)',
        'jabber'     : 'Jabber'
      };
      this.$el.html(this.template(template_values));
      return this;
    },

    setAddress: function(event) {
      this.model.set('address', $(event.target).val());
      if ( this.model.isValid() ) { this.addOrUpdate(this.model); }
    },
    setInterval: function(event) {
      this.model.set('interval', $(event.target).val());
      if ( this.model.isValid() ) { this.addOrUpdate(this.model); }
    },
    setRollupThreshold: function(event) {
      this.model.set('rollup_threshold', $(event.target).val());
      if ( this.model.isValid() ) { this.addOrUpdate(this.model); }
    },
    addOrUpdate: function(model) {
      var changedAttrKeys = _.keys(model.clean);
      var attrs = _.pick(model.attributes, changedAttrKeys);
      if ( model.isNew() ) {
        model.save(attrs);
        model.setPersisted(true);
        model.contact.addLinked('contacts', 'media', model);
      } else {
        model.patch('media', attrs);
      }
    }
  });

  Contact.Views.Entities = Backbone.View.extend({
    initialize: function(options) {
      this.options = options || {};
      this.template = _.template($('#contact-entities-template').html());
    },
    render: function() {
      var template_values = _.clone(this.options.contact.attributes);
      this.$el.html(this.template(template_values));

      var entityChooser = new Contact.Views.EntityChooser({contact: this.options.contact, current: this.options.current, all: this.options.all});
      this.$el.find('div#contactEntityChooser').replaceWith(entityChooser.render().$el);

      var entityList = new Contact.Views.EntityList({contact: this.options.contact, collection: this.options.current});
      this.$el.find('tbody#contactEntityList').replaceWith(entityList.render().$el);

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
      'change input#entityChooser' : 'chooserChanged'
    },
    initialize: function(options) {
      this.options = options || {};
      this.template = _.template($('#contact-entities-chooser-template').html());
      this.listenTo(options.current, 'add',    this.refresh);
      this.listenTo(options.current, 'remove', this.refresh);
    },
    chooserChanged: function(e) {
      if ( !_.isArray(e.removed) && _.isObject(e.removed) ) {
        this.entityIdsToAdd = _.without(this.entityIdsToAdd, e.removed.id);
      }

      if (  !_.isArray(e.added) && _.isObject(e.added) && (this.entityIdsToAdd.indexOf(e.added.id) == -1) ) {
        this.entityIdsToAdd.push(e.added.id);
      }
    },
    render: function() {
      this.calculate();

      // clear array
      this.entityIdsToAdd = new Array();

      this.$el.html(this.template({}));

      var jqel = $(this.el).find('input#entityChooser');

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

})(flapjack, flapjack.module("contact"));
