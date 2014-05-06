(function(flapjack, Medium) {
  // Shorthands
  // The application container
  var app = flapjack.app;

  Medium.Model = Backbone.JSONAPIModel.extend({
    name: 'media',
    defaults: {
      address: '',
      interval: 60,
      rollup_threshold: 3,
      id: null,
    },
    toJSON: function() {
      // TODO ensure that attributes has nothing outside the above, except 'links'
      // any use of 'contact_id' should use .links['contacts'][0]
      // any use of 'contact' should use .linked['contacts'][0]
      return _.pick(this.attributes, 'id', 'address', 'interval', 'rollup_threshold');
    },

    sync: function(method, model, options) {
      if ( method == 'create') {
        options.url = flapjack.api_url + '/contacts/' + model.get('contact_id') + '/' + this.name;
      // // this should be the default?
      // } else {
      //   options.url = model.urlRoot.call() + '/' + model.get('id');
      }
      Backbone.JSONAPIModel.prototype.sync(method, model, options);
    }

  });

  Medium.List = Backbone.JSONAPICollection.extend({
    model:      Medium.Model,
    comparator: 'type',
    url: function() { return flapjack.api_url + "/media"; }
  });

})(flapjack, flapjack.module("medium"));