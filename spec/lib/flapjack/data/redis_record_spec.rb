require 'spec_helper'
require 'flapjack/data/redis_record'

describe Flapjack::Data::RedisRecord, :redis => true do

  # TODO namespace when RedisRecord handles class names better
  class ::FdrrExample
    include Flapjack::Data::RedisRecord

    define_attribute_methods [:name, :email]

    validates :name, :presence => true

    index_by :name

    has_many :fdrr_children
  end

  class ::FdrrChild
    include Flapjack::Data::RedisRecord
    define_attribute_methods [:name]
    validates :name, :presence => true
  end

  let(:redis) { Flapjack.redis }

  def create_example
    redis.hmset('fdrrexample:8:attrs', {'name' => 'John Jones',
      'email' => 'jjones@example.com'}.flatten)
    redis.hmset('fdrrexample:by_name', {'John Jones' => '8'}.flatten)
    redis.sadd('fdrrexample::ids', '8')
  end

  def create_child
    redis.sadd('fdrrexample:8:fdrr_child_ids', '3')

    redis.sadd('fdrrchild::ids', '3')
    redis.hmset('fdrrchild:3:attrs', {'name' => 'Abel Tasman'}.flatten)
  end

  before(:each) do
    ::FdrrExample.redis = redis
  end

  it "is invalid without a name" do
    example = FdrrExample.new(:id => 1, :email => 'jsmith@example.com')
    example.should_not be_valid

    errs = example.errors
    errs.should_not be_nil
    errs[:name].should == ["can't be blank"]
  end

  it "adds a record's attributes to redis" do
    example = FdrrExample.new(:id => 1, :name => 'John Smith',
      :email => 'jsmith@example.com')
    example.should be_valid
    example.save.should be_true

    redis.keys('*').should =~ ['fdrrexample::ids', 'fdrrexample:1:attrs', 'fdrrexample:by_name']
    redis.smembers('fdrrexample::ids').should == ['1']
    redis.hgetall('fdrrexample:1:attrs').should == {'name' => 'John Smith',
      'email' => 'jsmith@example.com'}
    redis.hgetall('fdrrexample:by_name').should == {'John Smith' => '1'}
  end

  it "finds a record by id in redis" do
    create_example

    example = FdrrExample.find_by_id(8)
    example.should_not be_nil
    example.id.should == '8'
    example.name.should == 'John Jones'
    example.email.should == 'jjones@example.com'
  end

  it "finds a record by an indexed value in redis" do
    create_example

    example = FdrrExample.find_by(:name, 'John Jones')
    example.should_not be_nil
    example.id.should == '8'
    example.name.should == 'John Jones'
    example.email.should == 'jjones@example.com'
  end

  it "updates a record's attributes in redis" do
    create_example

    example = FdrrExample.find_by(:name, 'John Jones')
    example.name = 'Jane Janes'
    example.email = 'jjanes@example.com'
    example.save.should be_true

    redis.keys('*').should =~ ['fdrrexample::ids', 'fdrrexample:8:attrs', 'fdrrexample:by_name']
    redis.smembers('fdrrexample::ids').should == ['8']
    redis.hgetall('fdrrexample:8:attrs').should == {'name' => 'Jane Janes',
      'email' => 'jjanes@example.com'}
    redis.hgetall('fdrrexample:by_name').should == {'Jane Janes' => '8'}
  end

  it "deletes a record's attributes from redis" do
    create_example
    redis.keys('*').should =~ ['fdrrexample::ids', 'fdrrexample:8:attrs', 'fdrrexample:by_name']

    example = FdrrExample.find_by_id(8)
    example.destroy

    redis.keys('*').should == []
  end

  it "sets a parent/child has_many relationship between two records in redis" do
    create_example

    child = FdrrChild.new(:id => 3, :name => 'Abel Tasman')
    child.save.should be_true

    example = FdrrExample.find_by_id(8)
    example.fdrr_children << child

    redis.keys('*').should =~ ['fdrrexample::ids', 'fdrrexample:by_name',
      'fdrrexample:8:attrs', 'fdrrexample:8:fdrr_child_ids',
      'fdrrchild::ids', 'fdrrchild:3:attrs',]

    redis.smembers('fdrrexample::ids').should == ['8']
    redis.hgetall('fdrrexample:by_name').should == {'John Jones' => '8'}
    redis.hgetall('fdrrexample:8:attrs').should == {'name' => 'John Jones',
      'email' => 'jjones@example.com'}
    redis.smembers('fdrrexample:8:fdrr_child_ids').should == ['3']

    redis.smembers('fdrrchild::ids').should == ['3']
    redis.hgetall('fdrrchild:3:attrs').should == {'name' => 'Abel Tasman'}
  end

  it "loads a child from a parent's has_many relationship" do
    create_example
    create_child

    example = FdrrExample.find_by_id(8)
    children = example.fdrr_children.all

    children.should be_an(Array)
    children.should have(1).child
    child = children.first
    child.should be_a(FdrrChild)
    child.name.should == 'Abel Tasman'
  end

  it "removes a parent/child has_many relationship between two records in redis" do
    create_example
    create_child

    example = FdrrExample.find_by_id(8)
    child = FdrrChild.find_by_id(3)

    redis.smembers('fdrrchild::ids').should == ['3']
    redis.smembers('fdrrexample:8:fdrr_child_ids').should == ['3']

    example.fdrr_children.delete(child)

    redis.smembers('fdrrchild::ids').should == ['3']            # child not deleted
    redis.smembers('fdrrexample:8:fdrr_child_ids').should == [] # but association is
  end

  # it "sets a parent/child has_one relationship between two records in redis"

  # it "removes a parent/child has_one relationship between two records in redis"

end
