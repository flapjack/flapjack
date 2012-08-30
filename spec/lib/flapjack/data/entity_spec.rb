require 'spec_helper'
require 'flapjack/data/entity'

describe Flapjack::Data::Entity, :redis => true do

  let(:name)  { 'abc-123' }
  let(:check) { 'ping' }

  it "adds an entity, including contacts"

  it "finds an entity by name"

  it "creates an entity if allowed when it can't find it" do
    entity = Flapjack::Data::Entity.find_by_name(name, :redis => @redis, :create => true)

    entity.should_not be_nil
    entity.name.should == name
    @redis.get("entity_id:#{name}").should == ''
  end

  it "finds an entity by id"

  it "returns a list of all entities" do
    Flapjack::Data::Entity.add({'id'       => '5000',
                                'name'     => name},
                                :redis => @redis)
    Flapjack::Data::Entity.add({'id'       => '5001',
                                'name'     => "z_" + name},
                                :redis => @redis)

    entities = Flapjack::Data::Entity.all(:redis => @redis)
    entities.should_not be_nil
    entities.should be_an(Array)
    entities.should have(2).entities
    entities[0].id.should == 5000
    entities[1].id.should == 5001
  end

  it "returns a list of checks for an entity" do
    Flapjack::Data::Entity.add({'id'       => '5000',
                                'name'     => name},
                                :redis => @redis)

    @redis.hset("check:#{name}:ping", 'state', 'OK')
    @redis.hset("check:#{name}:ssh",  'state', 'OK')

    entity = Flapjack::Data::Entity.find_by_name(name, :redis => @redis)
    check_list = entity.check_list
    check_list.should_not be_nil
    check_list.should have(2).checks
    sorted_list = check_list.sort
    sorted_list[0].should == 'ping'
    sorted_list[1].should == 'ssh'
  end

  it "returns a count of checks for an entity" do
    Flapjack::Data::Entity.add({'id'       => '5000',
                                'name'     => name,
                                'contacts' => []},
                               :redis => @redis)

    @redis.hset("check:#{name}:ping", 'state', 'OK')
    @redis.hset("check:#{name}:ssh",  'state', 'OK')

    entity = Flapjack::Data::Entity.find_by_id(5000, :redis => @redis)
    check_count = entity.check_count
    check_count.should_not be_nil
    check_count.should == 2
  end

end