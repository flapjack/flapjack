(function(flapjack, Entity) {
  // Dependencies
  var Contact = flapjack.module("contact");

  // Shorthands
  // The application container
  var app = flapjack.app;

  Entity.Model = Backbone.JSONAPIModel.extend({
    name: 'entities',
    defaults: {
      name: '',
      id: null
    },
    toJSON: function() {
      // TODO ensure that attributes has nothing outside the above, except 'links'
      return _.pick(this.attributes, 'id', 'name');
    }
  });

  Entity.List = Backbone.JSONAPICollection.extend({
    model:      Entity.Model,
    comparator: 'name',
    url: function() { return flapjack.api_url + "/entities"; }
  });

})(flapjack, flapjack.module("entity"));