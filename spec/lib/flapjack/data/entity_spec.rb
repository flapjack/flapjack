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

    expect(entity0.tags).to include("source:foobar")
    expect(entity0.tags).to include("abc")
    expect(entity0.tags).not_to include("def")

    expect(entity1.tags).to include("source:foobar")
    expect(entity1.tags).to include("def")
    expect(entity1.tags).not_to include("abc")

    entities = Flapjack::Data::Entity.find_by_set_intersection(:tags, 'abc')
    expect(entities).to be_an(Array)
    expect(entities.size).to eq(1)
    expect(entities.first.id).to eq(entity0.id)

    entities = Flapjack::Data::Entity.find_by_set_intersection(:tags, 'source:foobar')
    expect(entities).to be_an(Array)
    expect(entities.size).to eq(2)
    expect(entities.map(&:id)).to match_array([entity0.id, entity1.id])

    entities = Flapjack::Data::Entity.find_by_set_intersection(:tags, 'source:foobar', 'def')
    expect(entities).to be_an(Array)
    expect(entities.size).to eq(1)
    expect(entities.first.id).to eq(entity1.id)

    entities = Flapjack::Data::Entity.find_by_set_intersection(:tags, 'donkey')
    expect(entities).to be_an(Array)
    expect(entities.size).to eq(0)
  end

end
