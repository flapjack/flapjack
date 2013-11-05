require 'spec_helper'
require 'flapjack/data/entity'

describe Flapjack::Data::Entity, :redis => true do

  # TODO move to redis_record spec, as the class method is defined there
  it "finds entities by tags" do
    entity0 = Flapjack::Data::Entity.new(:id   => '5000',
                                         :name => 'abc-123',
                                         :tags => Set.new(['source:foobar', 'abc']))
    entity0.save

    entity1 = Flapjack::Data::Entity.new(:id   => '5001',
                                         :name => 'def-456',
                                         :tags => Set.new(['source:foobar', 'def']))
    entity1.save

    entity0.tags.should include("source:foobar")
    entity0.tags.should include("abc")
    entity0.tags.should_not include("def")

    entity1.tags.should include("source:foobar")
    entity1.tags.should include("def")
    entity1.tags.should_not include("abc")

    entities = Flapjack::Data::Entity.find_by_set_intersection(:tags, 'abc')
    entities.should be_an(Array)
    entities.should have(1).entity
    entities.first.id.should == entity0.id

    entities = Flapjack::Data::Entity.find_by_set_intersection(:tags, 'source:foobar')
    entities.should be_an(Array)
    entities.should have(2).entities
    entities.map(&:id).should =~ [entity0.id, entity1.id]

    entities = Flapjack::Data::Entity.find_by_set_intersection(:tags, 'source:foobar', 'def')
    entities.should be_an(Array)
    entities.should have(1).entity
    entities.first.id.should == entity1.id

    entities = Flapjack::Data::Entity.find_by_set_intersection(:tags, 'donkey')
    entities.should be_an(Array)
    entities.should have(0).entities
  end

end
