require 'spec_helper'
require 'flapjack/data/entity'

describe Flapjack::Data::Entity, :redis => true do

  let(:name)  { 'abc-123' }
  let(:check) { 'ping' }

  it "creates an entity if allowed when it can't find it" do
    entity = Flapjack::Data::Entity.find_by_name(name, :create => true)

    entity.should_not be_nil
    entity.name.should == name
    Flapjack.redis.get("entity_id:#{name}").should == ''
  end

  it "adds a registered contact with an entity" do
    Flapjack::Data::Contact.add({'id'         => '362',
                                 'first_name' => 'John',
                                 'last_name'  => 'Johnson',
                                 'email'      => 'johnj@example.com' })

    Flapjack::Data::Entity.add({'id'   => '5000',
                                'name' => name,
                                'contacts' => ['362']})

    entity = Flapjack::Data::Entity.find_by_id('5000')
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
                                'contacts' => ['362']})

    entity = Flapjack::Data::Entity.find_by_id('5000')
    entity.should_not be_nil
    contacts = entity.contacts
    contacts.should_not be_nil
    contacts.should be_an(Array)
    contacts.should be_empty
  end

  it "finds an entity by id" do
    Flapjack::Data::Entity.add({'id'   => '5000',
                                'name' => name})

    entity = Flapjack::Data::Entity.find_by_id('5000')
    entity.should_not be_nil
    entity.name.should == name
  end

  it "finds an entity by name" do
    Flapjack::Data::Entity.add({'id'   => '5000',
                                'name' => name})

    entity = Flapjack::Data::Entity.find_by_name(name)
    entity.should_not be_nil
    entity.id.should == '5000'
  end

  it "returns a list of all entities" do
    Flapjack::Data::Entity.add({'id'   => '5000',
                                'name' => name})
    Flapjack::Data::Entity.add({'id'   => '5001',
                                'name' => "z_" + name})

    entities = Flapjack::Data::Entity.all
    entities.should_not be_nil
    entities.should be_an(Array)
    entities.should have(2).entities
    entities[0].id.should == '5000'
    entities[1].id.should == '5001'
  end

  it "returns a list of checks for an entity" do
    Flapjack::Data::Entity.add({'id'       => '5000',
                                'name'     => name})

    Flapjack.redis.zadd("current_checks:#{name}", Time.now.to_i, "ping")
    Flapjack.redis.zadd("current_checks:#{name}", Time.now.to_i, "ssh")

    entity = Flapjack::Data::Entity.find_by_name(name)
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
                                'contacts' => []})

    Flapjack.redis.zadd("current_checks:#{name}", Time.now.to_i, "ping")
    Flapjack.redis.zadd("current_checks:#{name}", Time.now.to_i, "ssh")

    entity = Flapjack::Data::Entity.find_by_id(5000)
    check_count = entity.check_count
    check_count.should_not be_nil
    check_count.should == 2
  end

  it "finds entity names matching a pattern" do
    Flapjack::Data::Entity.add({'id'       => '5000',
                                'name'     => 'abc-123',
                                'contacts' => []})

    Flapjack::Data::Entity.add({'id'       => '5001',
                                'name'     => 'def-456',
                                'contacts' => []})

    entities = Flapjack::Data::Entity.find_all_name_matching('abc')
    entities.should_not be_nil
    entities.should be_an(Array)
    entities.should have(1).entity
    entities.first.should == 'abc-123'
  end

  it "adds tags to entities" do
    entity = Flapjack::Data::Entity.add({'id'       => '5000',
                                         'name'     => 'abc-123',
                                         'contacts' => []})

    entity.add_tags('source:foobar', 'foo')

    entity.should_not be_nil
    entity.should be_an(Flapjack::Data::Entity)
    entity.name.should == 'abc-123'
    entity.tags.should include("source:foobar")
    entity.tags.should include("foo")

    # and test the tags as read back from redis
    entity = Flapjack::Data::Entity.find_by_id('5000')
    entity.tags.should include("source:foobar")
    entity.tags.should include("foo")

  end

  it "deletes tags from entities" do
    entity = Flapjack::Data::Entity.add({'id'       => '5000',
                                         'name'     => 'abc-123',
                                         'contacts' => []})

    entity.add_tags('source:foobar', 'foo')

    entity.should_not be_nil
    entity.tags.should include("source:foobar")
    entity.tags.should include("foo")

    entity.delete_tags('source:foobar')

    entity.tags.should_not include("source:foobar")
    entity.tags.should include("foo")

  end

  it "finds entities by tag" do
    entity0 = Flapjack::Data::Entity.add({'id'       => '5000',
                                          'name'     => 'abc-123',
                                          'contacts' => []})

    entity1 = Flapjack::Data::Entity.add({'id'       => '5001',
                                          'name'     => 'def-456',
                                          'contacts' => []})

    entity0.add_tags('source:foobar', 'abc')
    entity1.add_tags('source:foobar', 'def')

    entity0.should_not be_nil
    entity0.should be_an(Flapjack::Data::Entity)
    entity0.tags.should include("source:foobar")
    entity0.tags.should include("abc")
    entity0.tags.should_not include("def")
    entity1.should_not be_nil
    entity1.should be_an(Flapjack::Data::Entity)
    entity1.tags.should include("source:foobar")
    entity1.tags.should include("def")
    entity1.tags.should_not include("abc")

    entities = Flapjack::Data::Entity.find_all_with_tags(['abc'])
    entities.should be_an(Array)
    entities.should have(1).entity
    entities.first.should == 'abc-123'

    entities = Flapjack::Data::Entity.find_all_with_tags(['donkey'])
    entities.should be_an(Array)
    entities.should have(0).entities
  end

  it "finds entities with several tags" do
    entity0 = Flapjack::Data::Entity.add({'id'       => '5000',
                                         'name'     => 'abc-123',
                                         'contacts' => []})

    entity1 = Flapjack::Data::Entity.add({'id'       => '5001',
                                         'name'     => 'def-456',
                                         'contacts' => []})

    entity0.add_tags('source:foobar', 'abc')
    entity1.add_tags('source:foobar', 'def')

    entity0.should_not be_nil
    entity0.should be_an(Flapjack::Data::Entity)
    entity0.tags.should include("source:foobar")
    entity0.tags.should include("abc")
    entity1.should_not be_nil
    entity1.should be_an(Flapjack::Data::Entity)
    entity1.tags.should include("source:foobar")
    entity1.tags.should include("def")

    entities = Flapjack::Data::Entity.find_all_with_tags(['source:foobar'])
    entities.should be_an(Array)
    entities.should have(2).entity

    entities = Flapjack::Data::Entity.find_all_with_tags(['source:foobar', 'def'])
    entities.should be_an(Array)
    entities.should have(1).entity
    entities.first.should == 'def-456'
  end

end
