require 'spec_helper'
require 'flapjack/data/entity'

describe Flapjack::Data::Entity, :redis => true do

  let(:name)  { 'abc-123' }
  let(:check) { 'ping' }

  it "creates an entity if allowed when it can't find it" do
    entity = Flapjack::Data::Entity.find_by_name(name, :create => true)

    expect(entity).not_to be_nil
    expect(entity.name).to eq(name)
    expect(Flapjack.redis.get("entity_id:#{name}")).to eq('')
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
    expect(entity).not_to be_nil
    contacts = entity.contacts
    expect(contacts).not_to be_nil
    expect(contacts).to be_an(Array)
    expect(contacts.size).to eq(1)
    expect(contacts.first.name).to eq('John Johnson')
  end

  it "does not add a registered contact with an entity if the contact is unknown" do
    Flapjack::Data::Entity.add({'id'   => '5000',
                                'name' => name,
                                'contacts' => ['362']})

    entity = Flapjack::Data::Entity.find_by_id('5000')
    expect(entity).not_to be_nil
    contacts = entity.contacts
    expect(contacts).not_to be_nil
    expect(contacts).to be_an(Array)
    expect(contacts).to be_empty
  end

  it "finds an entity by id" do
    Flapjack::Data::Entity.add({'id'   => '5000',
                                'name' => name})

    entity = Flapjack::Data::Entity.find_by_id('5000')
    expect(entity).not_to be_nil
    expect(entity.name).to eq(name)
  end

  it "finds an entity by name" do
    Flapjack::Data::Entity.add({'id'   => '5000',
                                'name' => name})

    entity = Flapjack::Data::Entity.find_by_name(name)
    expect(entity).not_to be_nil
    expect(entity.id).to eq('5000')
  end

  it "returns a list of all entities" do
    Flapjack::Data::Entity.add({'id'   => '5000',
                                'name' => name})
    Flapjack::Data::Entity.add({'id'   => '5001',
                                'name' => "z_" + name})

    entities = Flapjack::Data::Entity.all
    expect(entities).not_to be_nil
    expect(entities).to be_an(Array)
    expect(entities.size).to eq(2)
    expect(entities[0].id).to eq('5000')
    expect(entities[1].id).to eq('5001')
  end

  it "returns a list of checks for an entity" do
    Flapjack::Data::Entity.add({'id'       => '5000',
                                'name'     => name})

    Flapjack.redis.zadd("current_checks:#{name}", Time.now.to_i, "ping")
    Flapjack.redis.zadd("current_checks:#{name}", Time.now.to_i, "ssh")

    entity = Flapjack::Data::Entity.find_by_name(name)
    check_list = entity.check_list
    expect(check_list).not_to be_nil
    expect(check_list.size).to eq(2)
    sorted_list = check_list.sort
    expect(sorted_list[0]).to eq('ping')
    expect(sorted_list[1]).to eq('ssh')
  end

  it "returns a count of checks for an entity" do
    Flapjack::Data::Entity.add({'id'       => '5000',
                                'name'     => name,
                                'contacts' => []})

    Flapjack.redis.zadd("current_checks:#{name}", Time.now.to_i, "ping")
    Flapjack.redis.zadd("current_checks:#{name}", Time.now.to_i, "ssh")

    entity = Flapjack::Data::Entity.find_by_id(5000)
    check_count = entity.check_count
    expect(check_count).not_to be_nil
    expect(check_count).to eq(2)
  end

  it "finds entity names matching a pattern" do
    Flapjack::Data::Entity.add({'id'       => '5000',
                                'name'     => 'abc-123',
                                'contacts' => []})

    Flapjack::Data::Entity.add({'id'       => '5001',
                                'name'     => 'def-456',
                                'contacts' => []})

    entities = Flapjack::Data::Entity.find_all_name_matching('abc')
    expect(entities).not_to be_nil
    expect(entities).to be_an(Array)
    expect(entities.size).to eq(1)
    expect(entities.first).to eq('abc-123')
  end

  it "adds tags to entities" do
    entity = Flapjack::Data::Entity.add({'id'       => '5000',
                                         'name'     => 'abc-123',
                                         'contacts' => []})

    entity.add_tags('source:foobar', 'foo')

    expect(entity).not_to be_nil
    expect(entity).to be_an(Flapjack::Data::Entity)
    expect(entity.name).to eq('abc-123')
    expect(entity.tags).to include("source:foobar")
    expect(entity.tags).to include("foo")

    # and test the tags as read back from redis
    entity = Flapjack::Data::Entity.find_by_id('5000')
    expect(entity.tags).to include("source:foobar")
    expect(entity.tags).to include("foo")

  end

  it "deletes tags from entities" do
    entity = Flapjack::Data::Entity.add({'id'       => '5000',
                                         'name'     => 'abc-123',
                                         'contacts' => []})

    entity.add_tags('source:foobar', 'foo')

    expect(entity).not_to be_nil
    expect(entity.tags).to include("source:foobar")
    expect(entity.tags).to include("foo")

    entity.delete_tags('source:foobar')

    expect(entity.tags).not_to include("source:foobar")
    expect(entity.tags).to include("foo")

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

    expect(entity0).not_to be_nil
    expect(entity0).to be_an(Flapjack::Data::Entity)
    expect(entity0.tags).to include("source:foobar")
    expect(entity0.tags).to include("abc")
    expect(entity0.tags).not_to include("def")
    expect(entity1).not_to be_nil
    expect(entity1).to be_an(Flapjack::Data::Entity)
    expect(entity1.tags).to include("source:foobar")
    expect(entity1.tags).to include("def")
    expect(entity1.tags).not_to include("abc")

    entities = Flapjack::Data::Entity.find_all_with_tags(['abc'])
    expect(entities).to be_an(Array)
    expect(entities.size).to eq(1)
    expect(entities.first).to eq('abc-123')

    entities = Flapjack::Data::Entity.find_all_with_tags(['donkey'])
    expect(entities).to be_an(Array)
    expect(entities.size).to eq(0)
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

    expect(entity0).not_to be_nil
    expect(entity0).to be_an(Flapjack::Data::Entity)
    expect(entity0.tags).to include("source:foobar")
    expect(entity0.tags).to include("abc")
    expect(entity1).not_to be_nil
    expect(entity1).to be_an(Flapjack::Data::Entity)
    expect(entity1.tags).to include("source:foobar")
    expect(entity1.tags).to include("def")

    entities = Flapjack::Data::Entity.find_all_with_tags(['source:foobar'])
    expect(entities).to be_an(Array)
    expect(entities.size).to eq(2)

    entities = Flapjack::Data::Entity.find_all_with_tags(['source:foobar', 'def'])
    expect(entities).to be_an(Array)
    expect(entities.size).to eq(1)
    expect(entities.first).to eq('def-456')
  end

end
