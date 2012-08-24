require 'spec_helper'
require 'flapjack/data/entity'

describe Flapjack::Data::Entity, :redis => true do

  let(:name)  { 'abc-123' }
  let(:check) { 'ping' }

  # copied from flapjack-populator -- TODO move to entity model
  def add_entity(entity = {})
    @redis.multi
    existing_name = @redis.hget("entity:#{entity['id']}", 'name')
    @redis.del("entity_id:#{existing_name}") unless existing_name == entity['name']
    @redis.set("entity_id:#{entity['name']}", entity['id'])
    @redis.hset("entity:#{entity['id']}", 'name', entity['name'])

    @redis.del("contacts_for:#{entity['id']}")
    if entity['contacts'] && entity['contacts'].respond_to?(:each)
      entity['contacts'].each {|contact|
        @redis.sadd("contacts_for:#{entity['id']}", contact)
      }
    end
    @redis.exec
  end

  it "returns a list of checks for an entity" do
    add_entity('id'       => '5000',
               'name'     => name,
               'contacts' => [])

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
    add_entity('id'       => '5000',
               'name'     => name,
               'contacts' => [])

    @redis.hset("check:#{name}:ping", 'state', 'OK')
    @redis.hset("check:#{name}:ssh",  'state', 'OK')

    entity = Flapjack::Data::Entity.find_by_name(name, :redis => @redis)
    check_count = entity.check_count
    check_count.should_not be_nil
    check_count.should == 2
  end

end