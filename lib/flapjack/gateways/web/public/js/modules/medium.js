(function(flapjack, Medium) {
  // Shorthands
  // The application container
  var app = flapjack.app;

  Medium.Model = Backbone.JSONAPIModel.extend({
    name: 'media',
    initialize: function(){
      this.on('change', this.setDirty, this);
    },
    defaults: {
      type: null,
      address: '',
      initial_failure_interval: 60,
      repeat_failure_interval: 60,
      rollup_threshold: 3,
      id: null,
      links: {},
    },
    toJSON: function() {
      return _.pick(this.attributes, 'id', 'type', 'address',
        'initial_failure_interval', 'repeat_failure_interval',
        'rollup_threshold');
    },
    sync: function(method, model, options) {
      if ( method == 'create') {
        options.url = flapjack.api_url + 'contacts/' + model.contact.get('id') + '/' + this.name;
      } else {
        options.url = flapjack.api_url + this.name + '/' + model.contact.get('id') + '_' + model.get('type');
      }
      Backbone.JSONAPIModel.prototype.sync(method, model, options);
    }

  });

  Medium.List = Backbone.JSONAPICollection.extend({
    model:      Medium.Model,
    comparator: 'type',
    url: function() { return flapjack.api_url + "media"; }
  });

})(flapjack, flapjack.module("medium"));
