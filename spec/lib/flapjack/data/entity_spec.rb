require 'spec_helper'
require 'flapjack/data/entity'

describe Flapjack::Data::Entity, :redis => true do

  let(:name)  { 'abc-123' }
  let(:check) { 'ping' }

  it "returns a list of checks for an entity" do
    @redis.hset("check:#{name}:ping", 'state', 'OK')
    @redis.hset("check:#{name}:ssh",  'state', 'OK')

    entity = Flapjack::Data::Entity.new(:entity => name, :redis => @redis)
    check_list = entity.check_list
    check_list.should_not be_nil
    check_list.should have(2).checks
    sorted_list = check_list.sort
    sorted_list[0].should == 'ping'
    sorted_list[1].should == 'ssh'
  end

  it "returns a count of checks for an entity" do
    @redis.hset("check:#{name}:ping", 'state', 'OK')
    @redis.hset("check:#{name}:ssh",  'state', 'OK')

    entity = Flapjack::Data::Entity.new(:entity => name, :redis => @redis)
    check_count = entity.check_count
    check_count.should_not be_nil
    check_count.should == 2
  end

end