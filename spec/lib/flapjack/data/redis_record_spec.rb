require 'spec_helper'
require 'flapjack/data/redis_record'

describe Flapjack::Data::RedisRecord, :redis => true do

  # TODO namespace when RedisRecord handles class names better
  class ::FDRRExample
    include Flapjack::Data::RedisRecord

    define_attribute_methods [:name, :email]

    validates :name, :presence => true

    index_by :name
  end

  let(:redis) { Flapjack.redis }

  before(:each) do
    ::FDRRExample.redis = redis
  end

  it "is invalid without a name" do
    example = FDRRExample.new(:id => 1, :email => 'jsmith@example.com')
    example.should_not be_valid

    errs = example.errors
    errs.should_not be_nil
    errs[:name].should == ["can't be blank"]
  end

  it "adds a record's attributes to redis" do
    example = FDRRExample.new(:id => 1, :name => 'John Smith',
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
    redis.hmset('fdrrexample:5:attrs', {'name' => 'John Jones',
      'email' => 'jjones@example.com'}.flatten)
    redis.hmset('fdrrexample:by_name', {'John Jones' => '5'}.flatten)
    redis.sadd('fdrrexample::ids', '5')

    example = FDRRExample.find_by_id(5)
    example.should_not be_nil
    example.id.should == '5'
    example.name.should == 'John Jones'
    example.email.should == 'jjones@example.com'
  end

  it "finds a record by an indexed value in redis" do
    redis.hmset('fdrrexample:8:attrs', {'name' => 'John Jones',
      'email' => 'jjones@example.com'}.flatten)
    redis.hmset('fdrrexample:by_name', {'John Jones' => '8'}.flatten)
    redis.sadd('fdrrexample::ids', '8')

    example = FDRRExample.find_by(:name, 'John Jones')
    example.should_not be_nil
    example.id.should == '8'
    example.name.should == 'John Jones'
    example.email.should == 'jjones@example.com'
  end

  it "updates a record's attributes in redis" do
    redis.hmset('fdrrexample:8:attrs', {'name' => 'John Jones',
      'email' => 'jjones@example.com'}.flatten)
    redis.hmset('fdrrexample:by_name', {'John Jones' => '8'}.flatten)
    redis.sadd('fdrrexample::ids', '8')

    example = FDRRExample.find_by(:name, 'John Jones')
    example.name = 'Jane Janes'
    example.email = 'jjanes@example.com'
    example.save.should be_true

    redis.keys('*').should =~ ['fdrrexample::ids', 'fdrrexample:8:attrs', 'fdrrexample:by_name']
    redis.smembers('fdrrexample::ids').should == ['8']
    redis.hgetall('fdrrexample:8:attrs').should == {'name' => 'Jane Janes',
      'email' => 'jjanes@example.com'}
    redis.hgetall('fdrrexample:by_name').should == {'Jane Janes' => '8'}
  end

  it "deletes a record's attributes from redis"

  it "sets a parent/child has_many relationship between two records in redis"

  it "removes a parent/child has_many relationship between two records in redis"

  it "sets a parent/child has_one relationship between two records in redis"

  it "removes a parent/child has_one relationship between two records in redis"

end
