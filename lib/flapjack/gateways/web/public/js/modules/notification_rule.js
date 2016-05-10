(function(flapjack, NotificationRule) {
  // Dependencies
  var Contact = flapjack.module("contact");

  // Shorthands
  // The application container
  var app = flapjack.app;

  NotificationRule.Model = Backbone.JSONAPIModel.extend({
    name: 'notification_rules',
    initialize: function(){
      Backbone.JSONAPIModel.prototype.initialize.apply(this, arguments);
      this.on('change', this.setDirty, this);
    },
    defaults: {
      id: null,
      tags: [],
      regex_tags: [],
      entities: [],
      regex_entities: [],
      time_restrictions: [],
      unknown_media: null,
      warning_media: [],
      critical_media: [],
      unknown_blackhole: false,
      warning_blackhole: false,
      critical_blackhole: false,
      links: {},
    },
    toJSON: function() {
      // TODO ensure that attributes has nothing outside the above, except 'links'
      return _.pick(this.attributes, 'id', 'tags', 'regex_tags', 'entities', 'regex_enities', 'time_restrictions', 'unknown_media', 'warning_media', 'critical_media', 'unknown_blackhole', 'warning_blackhole', 'critical_blackhole');
    },
    sync: function(method, model, options) {
      if ( method == 'create') {
        options.url = flapjack.api_url + 'contacts/' + model.contact.get('id') + '/' + this.name;
      } 
      Backbone.JSONAPIModel.prototype.sync(method, model, options);
    }
  });

  NotificationRule.List = Backbone.JSONAPICollection.extend({
    model:      NotificationRule.Model,
    comparator: 'id',
    url: function() { return flapjack.api_url + "notification_rules"; }
  });

})(flapjack, flapjack.module("notification_rule"));
