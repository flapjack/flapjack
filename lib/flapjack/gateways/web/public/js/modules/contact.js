(function(flapjack, Contact) {
  // Dependencies
  var Entity = flapjack.module("entity");
  var NotificationRule = flapjack.module("notification_rule");
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
      'click button.contact-media'              : 'editContactMedia',
      'click button.contact-entities'           : 'editContactEntities',
      'click button.contact-notification-rules' : 'editContactNotificationRules',
      'click button.delete-contact'             : 'removeContact',
      'click td'                                : 'editContactDetails'
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

    editContactNotificationRules: function(e) {
      e.stopImmediatePropagation();
      // skip if modal showing
      if ( $('#contactModal').hasClass('in') ) { return; }

      var deferreds = this.model.resolveLinks({notification_rules: NotificationRule.List});
      var allNotificationRules = new NotificationRule.List();

      deferreds.push(allNotificationRules.fetch());

      var context = this.model;

      $.when.apply($, deferreds).done(
        function() {
          var notificationRules = context.linked['notification_rules'];

          var notificationRulesView = new Contact.Views.NotificationRules({contact: context, current: notificationRules, all: allNotificationRules});
          $('div.modal-dialog').append(notificationRulesView.render().$el);
          $('div.modal-dialog').width(1200)

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

      _.each(['email', 'sms', 'slack', 'sms_twilio', 'sms_nexmo', 'sns', 'jabber', 'webhook'], function(type) {
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
        'jabber'     : 'Jabber',
        'webhook'    : 'Webhook'
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

  Contact.Views.NotificationRules = Backbone.View.extend({
    initialize: function(options) {
      this.options = options || {};
      this.template = _.template($('#contact-notification-rules-template').html());
    },
    events: {
      'click button#add-contact-notification-rule' : 'addNotificationRule',
    },
    render: function() {
      var template_values = _.clone(this.options.contact.attributes);
      this.$el.html(this.template(template_values));

      var notificationRuleList = new Contact.Views.NotificationRuleList({contact: this.options.contact, collection: this.options.current});
      this.$el.find('tbody#contactNotificationRuleList').replaceWith(notificationRuleList.render().$el);

      return this;
    },
    addNotificationRule: function(){
      var context = this;
      var notificationRule = new (NotificationRule.Model)();
      notificationRule.setPersisted(false);
      notificationRule.set('id', toolbox.generateUUID());

      var save_success = function(model, response, options) {
        model.setPersisted(true);
        model.contact.get('links')['notification_rules'].push(model.get('id'))
        model.contact.linked['notification_rules'].add(model);
      };
      var save_error = function(model, response, options) {
      };

      notificationRule.contact = this.options.contact
      notificationRule.save({}, {success: save_success, error: save_error});
    }

  });

  Contact.Views.NotificationRuleList = Backbone.View.extend({
    tagName: 'tbody',
    id: 'contactNotificationRuleList',
    initialize: function(options) {
      this.options = options || {};
      this.collection.on('add', this.render, this);
      this.collection.on('remove', this.render, this);
    },
    render: function() {
      var jqel = $(this.el);
      jqel.empty();
      var media = [{id: 'email'     ,text: 'Email'},
                   {id: 'sms'       ,text: 'SMS (MessageNet)'},
                   {id: 'slack'     ,text: 'Slack'},
                   {id: 'sms_twilio',text: 'SMS (Twilio)'},
                   {id: 'sms_nexmo' ,text: 'SMS (Nexmo)'},
                   {id: 'sns'       ,text: 'SMS (Amazon SNS)'},
                   {id: 'jabber'    ,text: 'Jabber'},
                   {id: 'pagerduty' ,text: 'PagerDuty'},
                   {id: 'webhook'   ,text: 'Webhook'}];
      var allEntities = new Entity.List();
      var contact = this.options.contact;
      var collection = this.collection;
      var fetch_success = function(entities, response, options) {
        collection.each(function(notificationRule) {
           var itemRo = new Contact.Views.NotificationRuleListItemReadOnly({ model: notificationRule, contact: contact});
           var item = new Contact.Views.NotificationRuleListItem({ model: notificationRule, contact: contact, media: media, entities: entities, itemRo: itemRo });
           jqel.append(itemRo.render().el);
           jqel.append(item.render().el);
        });
      }
      allEntities.fetch({success: fetch_success});

      return this;
    }
  });

  Contact.Views.NotificationRuleListItemReadOnly = Backbone.View.extend({
    tagName: 'tr',
    events: {
      'click button.edit-notification-rule'                  : 'editNotificationRule',
      'click button.delete-notification-rule'                : 'removeNotificationRule',
    },
    initialize: function(options) {
      this.options = options || {};
      this.template = _.template($('#contact-notification-rule-list-item-ro-template').html());
    },
    render: function() {
      var template_values = _.clone(this.model.attributes);

      this.$el.html(this.template(template_values));
      return this
    },
    editNotificationRule: function() {
      $(this.el).hide()
      $(this.el).closest('tr').next('tr').show()
    },
    removeNotificationRule: function() {
      this.options.contact.removeLinked('contacts', 'notification_rules', this.model);
      this.$el.remove();
    }
  });

  Contact.Views.NotificationRuleListItem = Backbone.View.extend({
    tagName: 'tr',
    events: {
      "change input[data-attr='entities']"                   : 'setEntities',
      "change textarea[data-attr='regex_entities']"          : 'setRegexEntities',
      "change input[data-attr='tags']"                       : 'setTags',
      "change textarea[data-attr='regex_tags']"              : 'setRegexTags',
      "change input[data-attr='warning_media']"              : 'setWarningMedia',
      "change input[data-attr='critical_media']"             : 'setCriticalMedia',
      "change textarea[data-attr='time_restrictions']"       : 'setTimeRestrictions',
      "click textarea[data-attr='time_restrictions']"        : 'clickTimeRestrictions',
      "change input[data-attr='unknown_blackhole']"          : 'setUnknownBlackhole',
      "change input[data-attr='warning_blackhole']"          : 'setWarningBlackhole',
      "change input[data-attr='critical_blackhole']"         : 'setCriticalBlackhole',
      'click button.close-edit-notification-rule'            : 'closeEditNotificationRule',
    },
    initialize: function(options) {
      this.options = options || {};
      this.template = _.template($('#contact-notification-rule-list-item-template').html());
    },
    render: function() {
      var template_values = _.clone(this.model.attributes);

      this.$el.html(this.template(template_values));
      $(this.el).hide()

      var format = function(item) { return item.text; }
      var format2 = function(item) { return item.name; }
     
      var ecel = $(this.el).find('input#'+this.model.attributes.id+'-entityChooser');
      var tcel = $(this.el).find('input#'+this.model.attributes.id+'-tagChooser');
      var wmel = $(this.el).find('input#'+this.model.attributes.id+'-warningMediaChooser');
      var cmel = $(this.el).find('input#'+this.model.attributes.id+'-criticalMediaChooser');

      var entities = this.options.entities.map( function(item) {
       var attributes = item.attributes;
       attributes.id = attributes.name;
        return attributes;
      });

      var tags = this.model.get('tags')

      ecel.select2({
        placeholder: "Select Entities",
        data: {results: entities, text: 'name'},
        formatSelection: format2,
        formatResult: format2,
        multiple: true,
        width: '100%',
      });

      tcel.select2({
        placeholder: "Tags:",
        tags: tags,
        multiple: true,
        width: '100%',
      });

      wmel.select2({
        placeholder: "Select Media",
        data: {results: this.options.media, text: 'text'},
        formatSelection: format,
        formatResult: format,
        multiple: true,
        width: '100%',
      });

      cmel.select2({
        placeholder: "Select Media",
        data: {results: this.options.media, text: 'text'},
        formatSelection: format,
        formatResult: format,
        multiple: true,
        width: '100%',
      });


      var trel = $(this.el).find('textarea#'+this.model.attributes.id+'-time_restrictions');
      this.timeRestriction = new Contact.Views.TimeRestriction ({parentEl: trel});
      trel.popover({
        title: 'Time Restriction',
        html: true,
        placement: 'left',
        trigger: 'manual',
        content: this.timeRestriction.render().$el.html(),
        width: '100%'
      }).on("hidden", function(e) {
        e.stopPropagation();
      });

      return this;
    },
    setEntities: function(event) {
      this.model.set('entities', $(event.target).val().split(','));
      if ( this.model.isValid() ) { this.update(this.model); }
    },
    setRegexEntities: function(event) {
      this.model.set('regex_entities', $(event.target).val().split(','));
      if ( this.model.isValid() ) { this.update(this.model); }
    },
    setTags: function(event) {
      this.model.set('tags', $(event.target).val().split(','));
      if ( this.model.isValid() ) { this.update(this.model); }
    },
    setRegexTags: function(event) {
      this.model.set('regex_tags', $(event.target).val().split(','));
      if ( this.model.isValid() ) { this.update(this.model); }
    },
    setWarningMedia: function(event) {
      this.model.set('warning_media', $(event.target).val().split(','));
      if ( this.model.isValid() ) { this.update(this.model); }
    },
    setCriticalMedia: function(event) {
      this.model.set('critical_media', $(event.target).val().split(','));
      if ( this.model.isValid() ) { this.update(this.model); }
    },
    setTimeRestrictions: function(event) {
      var timeRestrictions = [JSON.parse($(event.target).val())]
      this.model.set('time_restrictions', timeRestrictions)
      if ( this.model.isValid() ) { this.update(this.model); }
    },
    setUnknownBlackhole: function(event) {
      this.model.set('unknown_blackhole', $(event.target).is(":checked") );
      if ( this.model.isValid() ) { this.update(this.model); }
    },
    setWarningBlackhole: function(event) {
      this.model.set('warning_blackhole', $(event.target).is(":checked") );
      if ( this.model.isValid() ) { this.update(this.model); }
    },
    setCriticalBlackhole: function(event) {
      this.model.set('critical_blackhole', $(event.target).is(":checked") );
      if ( this.model.isValid() ) { this.update(this.model); }
    },
    update: function(model) {
      var changedAttrKeys = _.keys(model.clean);
      var attrs = _.pick(model.attributes, changedAttrKeys);
      model.patch('notification_rules', attrs);
    },
    clickTimeRestrictions: function(event) {
      $(event.target).popover('toggle')
      this.timeRestriction.setElement($(this.el).find('div.popover-content'));
      this.timeRestriction.render()
    },
    closeEditNotificationRule: function() {
      $(this.el).hide();
      this.options.itemRo.render();
      this.options.itemRo.$el.show();
    }
  });

  Contact.Views.TimeRestriction = Backbone.View.extend({
    tagName: 'div',
    className: 'popover-content',
    events:{
      'change input#rule-type'                               : 'setIntervalSuffix',
      "change input[name='day-of-options']"                  : 'setDayOfOption',
      'click button#set-time-restriction'                    : 'setTimeRestriction',
      'click button#cancel-time-restriction'                 : 'cancelTimeRestriction',
    },
    initialize: function(options) {
      this.options = options || {};
      this.template = _.template($('#contact-time-restriction-template').html());
    },
    render: function() {
      this.attributes = {startTime: '00:00', endTime: '00:00'}
      this.$el.html(this.template(this.attributes));
      var el = $(this.el)

      // add start date datepicker
      $(this.el).find('input#start-date').datepicker({
        changeMonth: true,
        numberOfMonths: 3,
        dateFormat: 'yy-mm-dd',
        onClose: function (selectedDate){
          el.find('input#end-date').datepicker("option", "minDate", selectedDate );
        }
      });
      $(this.el).find('input#start-date').datepicker("setDate", Date.now());

      // add start time timepicker
      $(this.el).find('input#start-time').timepicker({ timeFormat: 'H:i:s' });

      // add end date datepicker
      $(this.el).find('input#end-date').datepicker({
        changeMonth: true,
        numberOfMonths: 3,
        dateFormat: 'yy-mm-dd',
        onClose: function (selectedDate){
          el.find('input#start-date').datepicker("option", "maxDate", selectedDate );
        }
      });
      $(this.el).find('input#end-date').datepicker("setDate", Date.now());

      // add end time timepicker
      $(this.el).find('input#end-time').timepicker({ timeFormat: 'H:i:s' });


      this.ruleTypes = [
        {id: 0, text: 'Daily'},
        {id: 1, text: 'Weekly'},
        {id: 2, text: 'Monthly'},
        {id: 3, text: 'Yearly'},
      ]
      var format = function(item) { return item.text; }

      $(this.el).find('input#rule-type').select2({
        placeholder: "Select Ruletype",
        data: {results: this.ruleTypes, text: 'text'},
        formatSelection: format,
        formatResult: format,
        width: '100%',
      });

      $(this.el).find('#weekly-validations').append(_.template($('#contact-weekly-validations-template').html())).hide();
      $(this.el).find('#monthly-validations').append(_.template($('#contact-monthly-validations-template').html())).hide();

      var daysOfWeek=['S','M','T','W','T','F','S']
      var daybutton = _.template($('#contact-day-toggle-button-template').html());

      // add weekly day buttons
      for (var day=0; day<7; day ++) {
        $(this.el).find('#weekly-days').append(daybutton({
          id: 'weekly-day-' + day.toString(),
          value: day,
          day: daysOfWeek[day],
          width: '30px'
        }));
      }

      // add day of month buttons
      for (var day=1; day<=31; day++) { 
        $(this.el).find('#day-of-month').append(daybutton({
          id: 'monthly-day-' + day.toString(),
          value: day,
          day: day,
          width: '26px'
        }));
      }
      $(this.el).find('#day-of-month').append(daybutton({
        id: 'monthly-day-0',
        value: 0,
        day: 'Last Day',
        width: '101px'
      }));

      // add day of week buttons
      var el = $(this.el)
      _.each(['1st','2nd','3th','4th'], function(week) {
        for (var day=0; day<7; day ++) {
          el.find('#monthly-' + week + '-week').append(daybutton({
            id: 'monthly-' + week + '-week-day-' + day.toString(),
            value: day,
            day: daysOfWeek[day],
            width: '30px'
          }));
        }
      });
      $(this.el).find('#day-of-month').show();
      $(this.el).find('#day-of-week').hide();

      return this
    },
    setIntervalSuffix: function(event) {
      switch($(event.target).val()){
        case '0': $(this.el).find('#interval-suffix').text('day(s)');
                  $(this.el).find('#weekly-validations').hide();
                  $(this.el).find('#monthly-validations').hide();
                  break;
        case '1': $(this.el).find('#interval-suffix').text('week(s) on:');
                  $(this.el).find('#weekly-validations').show();
                  $(this.el).find('#monthly-validations').hide();
                  break;
        case '2': $(this.el).find('#interval-suffix').text('month(s)');
                  $(this.el).find('#weekly-validations').hide();
                  $(this.el).find('#monthly-validations').show();
                  break;
        case '3': $(this.el).find('#interval-suffix').text('year(s)');
                  $(this.el).find('#weekly-validations').hide();
                  $(this.el).find('#monthly-validations').hide();
                  break;
      }
    },
    setDayOfOption: function(event) {
      switch($(event.target).val()){
        case 'day-of-month':
          $(this.el).find('#day-of-month').show();
          $(this.el).find('#day-of-week').hide();
          break;
        case 'day-of-week':
          $(this.el).find('#day-of-week').show();
          $(this.el).find('#day-of-month').hide();
          break;
      }
    },
    setTimeRestriction: function() {
      var el = $(this.el)
      var timeRestriction = {}
      timeRestriction.start_time = el.find('#start-date').val() + ' ' + el.find('#start-time').val();
      timeRestriction.end_time = el.find('#end-date').val() + ' ' + el.find('#end-time').val();

      // set rrule
      var rrule = {}
      var rule_type = _.find(this.ruleTypes, function(item) {
        return item.id == el.find('#rule-type').val();
      });
      rrule.rule_type = rule_type.text

      // set rrule.validations
      switch(rule_type.id){
        case 1:
          // Weekly validations
          rrule.validations = this.getWeeklyRule()
          rrule.week_start = 0
          break;
        case 2:
          if (el.find("input[name='day-of-options']:checked").val() == 'day-of-month') {
            // Monthly (by day of month) Validations
            rrule.validations = this.getMonthlyByDayOfMonthRule()
          } else {
            // Monthly (by day of Nth week) Validations
            rrule.validations = this.getMonthlyByDayOfWeekRule()
          }
          break;
        default :
          rrule.validations = {}
          break;
      }
      rrule.interval = parseInt(el.find('#interval').val());
      timeRestriction.rrules = [rrule]
      timeRestriction.exrules = []
      timeRestriction.rtimes = []
      timeRestriction.extimes = []

      this.options.parentEl.val(JSON.stringify(timeRestriction));
      this.options.parentEl.change();
      this.options.parentEl.popover('hide')
    },
    getWeeklyRule: function() {
      var days_of_week = [];
      for (day=0; day<7; day++){
        if ($(this.el).find('#weekly-day-' + day).prop('checked')) {days_of_week.push(day)}
      }
      return {day: days_of_week}
    },
    getMonthlyByDayOfMonthRule: function() {
      var days_of_month = [];
      for (day=0; day<32; day++){
        if ($(this.el).find('#monthly-day-' + day).prop('checked')) {days_of_month.push(day)}
      }
      return { day_of_month: _.map(days_of_month, function(day) {return day == 0 ? -1 : day})}
    },
    getMonthlyByDayOfWeekRule: function() {
      var weeks = ['1st','2nd','3th','4th'];
      var days = ['sunday','monday','tuesday', 'wednesday','thursday','friday','saturday'];
      var dayOfWeek = {};
      var el = $(this.el);

      for (day=0; day<7; day++) {
        for (week=0; week<4; week++) {
          if (el.find('#monthly-' + weeks[week] + '-week-day-' + day).prop('checked')) {
            dayOfWeek[days[day]] = typeof dayOfWeek[days[day]] == 'undefined' ? [] : dayOfWeek[days[day]]
            dayOfWeek[days[day]].push(week + 1)
          }
        }
      }
      return { day_of_week: dayOfWeek }
    },
    cancelTimeRestriction: function(event) {
      this.options.parentEl.popover('hide')
    }

  });
})(flapjack, flapjack.module("contact"));
