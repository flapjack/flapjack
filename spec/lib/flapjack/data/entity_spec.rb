require 'spec_helper'
require 'flapjack/data/entity'

describe Flapjack::Data::Entity, :redis => true do

  let(:name)  { 'abc-123' }
  let(:check) { 'ping' }

  it "creates an entity if allowed when it can't find it" do
    entity = Flapjack::Data::Entity.find_by_name(name, :redis => @redis, :create => true)

    entity.should_not be_nil
    entity.name.should == name
    @redis.get("entity_id:#{name}").should == ''
  end

  it "adds a registered contact with an entity" do
    Flapjack::Data::Contact.add({'id'         => '362',
                                 'first_name' => 'John',
                                 'last_name'  => 'Johnson',
                                 'email'      => 'johnj@example.com' },
                                 :redis       => @redis)

    Flapjack::Data::Entity.add({'id'   => '5000',
                                'name' => name,
                                'contacts' => ['362']},
                                :redis => @redis)

    entity = Flapjack::Data::Entity.find_by_id('5000', :redis => @redis)
    entity.should_not be_nil
    contacts = entity.contacts
    contacts.should_not be_nil
    contacts.should be_an(Array)
    contacts.should have(1).contact
    contacts.first.name.should == 'John Johnson'
  end

  it "does not add a registered contact with an entity if the contact is unknown" do
    Flapjack::Data::Entity.add({'id'   => '5000',
                                'name' => name,
                                'contacts' => ['362']},
                                :redis => @redis)

    entity = Flapjack::Data::Entity.find_by_id('5000', :redis => @redis)
    entity.should_not be_nil
    contacts = entity.contacts
    contacts.should_not be_nil
    contacts.should be_an(Array)
    contacts.should be_empty
  end

  it "finds an entity by id" do
    Flapjack::Data::Entity.add({'id'   => '5000',
                                'name' => name},
                                :redis => @redis)

    entity = Flapjack::Data::Entity.find_by_id('5000', :redis => @redis)
    entity.should_not be_nil
    entity.name.should == name
  end

  it "finds an entity by name" do
    Flapjack::Data::Entity.add({'id'   => '5000',
                                'name' => name},
                                :redis => @redis)

    entity = Flapjack::Data::Entity.find_by_name(name, :redis => @redis)
    entity.should_not be_nil
    entity.id.should == '5000'
  end

  it "returns a list of all entities" do
    Flapjack::Data::Entity.add({'id'   => '5000',
                                'name' => name},
                                :redis => @redis)
    Flapjack::Data::Entity.add({'id'   => '5001',
                                'name' => "z_" + name},
                                :redis => @redis)

    entities = Flapjack::Data::Entity.all(:redis => @redis)
    entities.should_not be_nil
    entities.should be_an(Array)
    entities.should have(2).entities
    entities[0].id.should == '5000'
    entities[1].id.should == '5001'
  end

  it "returns a list of checks for an entity" do
    Flapjack::Data::Entity.add({'id'       => '5000',
                                'name'     => name},
                                :redis => @redis)

    @redis.zadd("current_checks:#{name}", Time.now.to_i, "ping")
    @redis.zadd("current_checks:#{name}", Time.now.to_i, "ssh")

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

    @redis.zadd("current_checks:#{name}", Time.now.to_i, "ping")
    @redis.zadd("current_checks:#{name}", Time.now.to_i, "ssh")

    entity = Flapjack::Data::Entity.find_by_id(5000, :redis => @redis)
    check_count = entity.check_count
    check_count.should_not be_nil
    check_count.should == 2
  end

  it "finds entity names matching a pattern" do
    Flapjack::Data::Entity.add({'id'       => '5000',
                                'name'     => 'abc-123',
                                'contacts' => []},
                               :redis => @redis)

    Flapjack::Data::Entity.add({'id'       => '5001',
                                'name'     => 'def-456',
                                'contacts' => []},
                               :redis => @redis)

    entities = Flapjack::Data::Entity.find_all_name_matching('abc', :redis => @redis)
    entities.should_not be_nil
    entities.should be_an(Array)
    entities.should have(1).entity
    entities.first.should == 'abc-123'
  end

  it "adds tags to entities" do
    entity = Flapjack::Data::Entity.add({'id'       => '5000',
                                         'name'     => 'abc-123',
                                         'contacts' => []},
                                        :redis => @redis)

    entity.add_tags('source:foobar', 'foo')

    entity.should_not be_nil
    entity.should be_an(Flapjack::Data::Entity)
    entity.name.should == 'abc-123'
    entity.tags.should include("source:foobar")
    entity.tags.should include("foo")

    # and test the tags as read back from redis
    entity = Flapjack::Data::Entity.find_by_id('5000', :redis => @redis)
    entity.tags.should include("source:foobar")
    entity.tags.should include("foo")

  end

  it "deletes tags from entities" do
    entity = Flapjack::Data::Entity.add({'id'       => '5000',
                                         'name'     => 'abc-123',
                                         'contacts' => []},
                                        :redis => @redis)

    entity.add_tags('source:foobar', 'foo')

    entity.should_not be_nil
    entity.tags.should include("source:foobar")
    entity.tags.should include("foo")

    entity.delete_tags('source:foobar')

    entity.tags.should_not include("source:foobar")
    entity.tags.should include("foo")

  end

  it "finds entities by tag" do
    entity = Flapjack::Data::Entity.add({'id'       => '5000',
                                         'name'     => 'abc-123',
                                         'contacts' => []},
                                        :redis => @redis)

    entity.add_tags('source:foobar', 'foo')

    entity.should_not be_nil
    entity.should be_an(Flapjack::Data::Entity)
    # TODO - the rest of it
  end

end
