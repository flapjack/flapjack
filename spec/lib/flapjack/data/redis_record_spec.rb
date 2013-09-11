require 'spec_helper'
require 'flapjack/data/redis_record'

describe Flapjack::Data::RedisRecord, :redis => true do

  class Flapjack::Data::RedisRecord::ExampleChild
    include Flapjack::Data::RedisRecord
    define_attributes :name => :string
    validates :name, :presence => true
  end

  class Flapjack::Data::RedisRecord::Example
    include Flapjack::Data::RedisRecord

    define_attributes :name  => :string,
                      :email => :string

    validates :name, :presence => true

    index_by :name

    has_many :fdrr_children, :class => Flapjack::Data::RedisRecord::ExampleChild
  end

  let(:redis) { Flapjack.redis }

  def create_example
    redis.hmset('flapjack/data/redis_record/example:8:attrs',
      {'name' => 'John Jones', 'email' => 'jjones@example.com'}.flatten)
    redis.hmset('flapjack/data/redis_record/example:by_name',
      {'John Jones' => '8'}.flatten)
    redis.sadd('flapjack/data/redis_record/example::ids', '8')
  end

  def create_child
    redis.sadd('flapjack/data/redis_record/example:8:fdrr_child_ids', '3')

    redis.sadd('flapjack/data/redis_record/example_child::ids', '3')
    redis.hmset('flapjack/data/redis_record/example_child:3:attrs',
                {'name' => 'Abel Tasman'}.flatten)
  end

  it "is invalid without a name" do
    example = Flapjack::Data::RedisRecord::Example.new(:id => 1, :email => 'jsmith@example.com')
    example.should_not be_valid

    errs = example.errors
    errs.should_not be_nil
    errs[:name].should == ["can't be blank"]
  end

  it "adds a record's attributes to redis" do
    example = Flapjack::Data::RedisRecord::Example.new(:id => 1, :name => 'John Smith',
      :email => 'jsmith@example.com')
    example.should be_valid
    example.save.should be_true

    redis.keys('*').should =~ ['flapjack/data/redis_record/example::ids',
                               'flapjack/data/redis_record/example:1:attrs',
                               'flapjack/data/redis_record/example:by_name']
    redis.smembers('flapjack/data/redis_record/example::ids').should == ['1']
    redis.hgetall('flapjack/data/redis_record/example:1:attrs').should ==
      {'name' => 'John Smith', 'email' => 'jsmith@example.com'}
    redis.hgetall('flapjack/data/redis_record/example:by_name').should ==
      {'John Smith' => '1'}
  end

  it "finds a record by id in redis" do
    create_example

    example = Flapjack::Data::RedisRecord::Example.find_by_id(8)
    example.should_not be_nil
    example.id.should == '8'
    example.name.should == 'John Jones'
    example.email.should == 'jjones@example.com'
  end

  it "finds a record by an indexed value in redis" do
    create_example

    example = Flapjack::Data::RedisRecord::Example.find_by(:name, 'John Jones')
    example.should_not be_nil
    example.id.should == '8'
    example.name.should == 'John Jones'
    example.email.should == 'jjones@example.com'
  end

  it "updates a record's attributes in redis" do
    create_example

    example = Flapjack::Data::RedisRecord::Example.find_by(:name, 'John Jones')
    example.name = 'Jane Janes'
    example.email = 'jjanes@example.com'
    example.save.should be_true

    redis.keys('*').should =~ ['flapjack/data/redis_record/example::ids',
                               'flapjack/data/redis_record/example:8:attrs',
                               'flapjack/data/redis_record/example:by_name']
    redis.smembers('flapjack/data/redis_record/example::ids').should == ['8']
    redis.hgetall('flapjack/data/redis_record/example:8:attrs').should ==
      {'name' => 'Jane Janes', 'email' => 'jjanes@example.com'}
    redis.hgetall('flapjack/data/redis_record/example:by_name').should ==
      {'Jane Janes' => '8'}
  end

  it "deletes a record's attributes from redis" do
    create_example
    redis.keys('*').should =~ ['flapjack/data/redis_record/example::ids',
                               'flapjack/data/redis_record/example:8:attrs',
                               'flapjack/data/redis_record/example:by_name']

    example = Flapjack::Data::RedisRecord::Example.find_by_id(8)
    example.destroy

    redis.keys('*').should == []
  end

  it "sets a parent/child has_many relationship between two records in redis" do
    create_example

    child = Flapjack::Data::RedisRecord::ExampleChild.new(:id => 3, :name => 'Abel Tasman')
    child.save.should be_true

    example = Flapjack::Data::RedisRecord::Example.find_by_id(8)
    example.fdrr_children << child

    redis.keys('*').should =~ ['flapjack/data/redis_record/example::ids',
                               'flapjack/data/redis_record/example:by_name',
                               'flapjack/data/redis_record/example:8:attrs',
                               'flapjack/data/redis_record/example:8:fdrr_child_ids',
                               'flapjack/data/redis_record/example_child::ids',
                               'flapjack/data/redis_record/example_child:3:attrs']

    redis.smembers('flapjack/data/redis_record/example::ids').should == ['8']
    redis.hgetall('flapjack/data/redis_record/example:by_name').should ==
      {'John Jones' => '8'}
    redis.hgetall('flapjack/data/redis_record/example:8:attrs').should ==
      {'name' => 'John Jones', 'email' => 'jjones@example.com'}
    redis.smembers('flapjack/data/redis_record/example:8:fdrr_child_ids').should == ['3']

    redis.smembers('flapjack/data/redis_record/example_child::ids').should == ['3']
    redis.hgetall('flapjack/data/redis_record/example_child:3:attrs').should ==
      {'name' => 'Abel Tasman'}
  end

  it "loads a child from a parent's has_many relationship" do
    create_example
    create_child

    example = Flapjack::Data::RedisRecord::Example.find_by_id(8)
    children = example.fdrr_children.all

    children.should be_an(Array)
    children.should have(1).child
    child = children.first
    child.should be_a(Flapjack::Data::RedisRecord::ExampleChild)
    child.name.should == 'Abel Tasman'
  end

  it "removes a parent/child has_many relationship between two records in redis" do
    create_example
    create_child

    example = Flapjack::Data::RedisRecord::Example.find_by_id(8)
    child = Flapjack::Data::RedisRecord::ExampleChild.find_by_id(3)

    redis.smembers('flapjack/data/redis_record/example_child::ids').should == ['3']
    redis.smembers('flapjack/data/redis_record/example:8:fdrr_child_ids').should == ['3']

    example.fdrr_children.delete(child)

    redis.smembers('flapjack/data/redis_record/example_child::ids').should == ['3']    # child not deleted
    redis.smembers('flapjack/data/redis_record/example:8:fdrr_child_ids').should == [] # but association is
  end

  # it "sets a parent/child has_one relationship between two records in redis"

  # it "removes a parent/child has_one relationship between two records in redis"

  it "resets changed state on refresh" do
    create_example
    example = Flapjack::Data::RedisRecord::Example.find_by_id(8)

    example.name = "King Henry VIII"
    example.changed.should include('name')
    example.changes.should == {'name' => ['John Jones', 'King Henry VIII']}

    example.refresh
    example.changed.should be_empty
    example.changes.should be_empty
  end

  # TODO validate updates of the different data types for attributes

end
