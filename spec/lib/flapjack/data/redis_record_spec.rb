require 'spec_helper'
require 'flapjack/data/redis_record'

describe Flapjack::Data::RedisRecord, :redis => true do

  class Flapjack::Data::RedisRecord::Example
    include Flapjack::Data::RedisRecord

    define_attributes :name   => :string,
                      :email  => :string,
                      :active => :boolean

    validates :name, :presence => true

    index_by :active
  end

  let(:redis) { Flapjack.redis }

  def create_example(attrs = {})
    redis.hmset("flapjack/data/redis_record/example:#{attrs[:id]}:attrs",
      {'name' => attrs[:name], 'email' => attrs[:email], 'active' => attrs[:active]}.flatten)
    redis.sadd("flapjack/data/redis_record/example::by_active:#{!!attrs[:active]}", attrs[:id])
    redis.sadd('flapjack/data/redis_record/example::ids', attrs[:id])
  end

  it "is invalid without a name" do
    example = Flapjack::Data::RedisRecord::Example.new(:id => '1', :email => 'jsmith@example.com')
    example.should_not be_valid

    errs = example.errors
    errs.should_not be_nil
    errs[:name].should == ["can't be blank"]
  end

  it "adds a record's attributes to redis" do
    example = Flapjack::Data::RedisRecord::Example.new(:id => '1', :name => 'John Smith',
      :email => 'jsmith@example.com', :active => true)
    example.should be_valid
    example.save.should be_true

    redis.keys('*').should =~ ['flapjack/data/redis_record/example::ids',
                               'flapjack/data/redis_record/example:1:attrs',
                               'flapjack/data/redis_record/example::by_active:true']
    redis.smembers('flapjack/data/redis_record/example::ids').should == ['1']
    redis.hgetall('flapjack/data/redis_record/example:1:attrs').should ==
      {'name' => 'John Smith', 'email' => 'jsmith@example.com', 'active' => 'true'}
    redis.smembers('flapjack/data/redis_record/example::by_active:true').should ==
      ['1']
  end

  it "finds a record by id in redis" do
    create_example(:id => '8', :name => 'John Jones',
                   :email => 'jjones@example.com', :active => 'true')

    example = Flapjack::Data::RedisRecord::Example.find_by_id('8')
    example.should_not be_nil
    example.id.should == '8'
    example.name.should == 'John Jones'
    example.email.should == 'jjones@example.com'
  end

  it "finds records by an indexed value in redis" do
    create_example(:id => '8', :name => 'John Jones',
                   :email => 'jjones@example.com', :active => 'true')

    examples = Flapjack::Data::RedisRecord::Example.intersect(:active => true).all
    examples.should_not be_nil
    examples.should be_an(Array)
    examples.should have(1).example
    example = examples.first
    example.id.should == '8'
    example.name.should == 'John Jones'
    example.email.should == 'jjones@example.com'
  end

  it "updates a record's attributes in redis" do
    create_example(:id => '8', :name => 'John Jones',
                   :email => 'jjones@example.com', :active => 'true')

    example = Flapjack::Data::RedisRecord::Example.find_by_id('8')
    example.name = 'Jane Janes'
    example.email = 'jjanes@example.com'
    example.save.should be_true

    redis.keys('*').should =~ ['flapjack/data/redis_record/example::ids',
                               'flapjack/data/redis_record/example:8:attrs',
                               'flapjack/data/redis_record/example::by_active:true']
    redis.smembers('flapjack/data/redis_record/example::ids').should == ['8']
    redis.hgetall('flapjack/data/redis_record/example:8:attrs').should ==
      {'name' => 'Jane Janes', 'email' => 'jjanes@example.com', 'active' => 'true'}
    redis.smembers('flapjack/data/redis_record/example::by_active:true').should ==
      ['8']
  end

  it "deletes a record's attributes from redis" do
    create_example(:id => '8', :name => 'John Jones',
                   :email => 'jjones@example.com', :active => 'true')

    redis.keys('*').should =~ ['flapjack/data/redis_record/example::ids',
                               'flapjack/data/redis_record/example:8:attrs',
                               'flapjack/data/redis_record/example::by_active:true']

    example = Flapjack::Data::RedisRecord::Example.find_by_id('8')
    example.destroy

    redis.keys('*').should == []
  end

  it "resets changed state on refresh" do
    create_example(:id => '8', :name => 'John Jones',
                   :email => 'jjones@example.com', :active => 'true')
    example = Flapjack::Data::RedisRecord::Example.find_by_id('8')

    example.name = "King Henry VIII"
    example.changed.should include('name')
    example.changes.should == {'name' => ['John Jones', 'King Henry VIII']}

    example.refresh
    example.changed.should be_empty
    example.changes.should be_empty
  end

  it "stores a string as an attribute value"
  it "stores an integer as an attribute value"
  it "stores a timestamp as an attribute value"
  it "stores a boolean as an attribute value"

  it "stores a list as an attribute value"
  it "stores a set as an attribute value"
  it "stores a hash as an attribute value"

  it "stores a complex attribute value as JSON"

  context 'filters' do

    it "filters all class records by indexed attribute values" do
      create_example(:id => '8', :name => 'John Jones',
                     :email => 'jjones@example.com', :active => true)
      example = Flapjack::Data::RedisRecord::Example.find_by_id('8')

      create_example(:id => '9', :name => 'James Brown',
                     :email => 'jbrown@example.com', :active => false)
      example_2 = Flapjack::Data::RedisRecord::Example.find_by_id('9')

      active = Flapjack::Data::RedisRecord::Example.intersect(:active => true).all
      active.should_not be_nil
      active.should be_an(Array)
      active.should have(1).example
      active.map(&:id).should =~ ['8']
    end

    it 'supports sequential intersection and union operations'

    it 'allows intersection operations across multiple values for an attribute'

    it 'allows union operations across multiple values for an attribute'

  end


  context "has_many" do

    class Flapjack::Data::RedisRecord::ExampleChild
      include Flapjack::Data::RedisRecord

      define_attributes :name => :string,
                        :important => :boolean

      index_by :important

      belongs_to :example, :class_name => 'Flapjack::Data::RedisRecord::Example'

      validates :name, :presence => true
    end

    class Flapjack::Data::RedisRecord::Example
      has_many :fdrr_children, :class_name => 'Flapjack::Data::RedisRecord::ExampleChild'
    end

    def create_child(parent, attrs = {})
      redis.sadd("flapjack/data/redis_record/example:#{parent.id}:fdrr_children_ids", attrs[:id])

      redis.hmset("flapjack/data/redis_record/example_child:#{attrs[:id]}:attrs",
                  {'name' => attrs[:name], 'important' => !!attrs[:important]}.flatten)

      redis.sadd("flapjack/data/redis_record/example_child::by_important:#{!!attrs[:important]}", attrs[:id])

      redis.sadd('flapjack/data/redis_record/example_child::ids', attrs[:id])
    end

    it "sets a parent/child has_many relationship between two records in redis" do
      create_example(:id => '8', :name => 'John Jones',
                     :email => 'jjones@example.com', :active => 'true')

      child = Flapjack::Data::RedisRecord::ExampleChild.new(:id => '3', :name => 'Abel Tasman')
      child.save.should be_true

      example = Flapjack::Data::RedisRecord::Example.find_by_id('8')
      example.fdrr_children << child

      redis.keys('*').should =~ ['flapjack/data/redis_record/example::ids',
                                 'flapjack/data/redis_record/example::by_active:true',
                                 'flapjack/data/redis_record/example:8:attrs',
                                 'flapjack/data/redis_record/example:8:fdrr_children_ids',
                                 'flapjack/data/redis_record/example_child::ids',
                                 'flapjack/data/redis_record/example_child:3:attrs']

      redis.smembers('flapjack/data/redis_record/example::ids').should == ['8']
      redis.smembers('flapjack/data/redis_record/example::by_active:true').should ==
        ['8']
      redis.hgetall('flapjack/data/redis_record/example:8:attrs').should ==
        {'name' => 'John Jones', 'email' => 'jjones@example.com', 'active' => 'true'}
      redis.smembers('flapjack/data/redis_record/example:8:fdrr_children_ids').should == ['3']

      redis.smembers('flapjack/data/redis_record/example_child::ids').should == ['3']
      redis.hgetall('flapjack/data/redis_record/example_child:3:attrs').should ==
        {'name' => 'Abel Tasman'}
    end

    it "loads a child from a parent's has_many relationship" do
      create_example(:id => '8', :name => 'John Jones',
                     :email => 'jjones@example.com', :active => 'true')
      example = Flapjack::Data::RedisRecord::Example.find_by_id('8')
      create_child(example, :id => '3', :name => 'Abel Tasman')

      children = example.fdrr_children.all

      children.should be_an(Array)
      children.should have(1).child
      child = children.first
      child.should be_a(Flapjack::Data::RedisRecord::ExampleChild)
      child.name.should == 'Abel Tasman'
    end

    it "removes a parent/child has_many relationship between two records in redis" do
      create_example(:id => '8', :name => 'John Jones',
                     :email => 'jjones@example.com', :active => 'true')
      example = Flapjack::Data::RedisRecord::Example.find_by_id('8')

      create_child(example, :id => '3', :name => 'Abel Tasman')
      child = Flapjack::Data::RedisRecord::ExampleChild.find_by_id('3')

      redis.smembers('flapjack/data/redis_record/example_child::ids').should == ['3']
      redis.smembers('flapjack/data/redis_record/example:8:fdrr_children_ids').should == ['3']

      example.fdrr_children.delete(child)

      redis.smembers('flapjack/data/redis_record/example_child::ids').should == ['3']    # child not deleted
      redis.smembers('flapjack/data/redis_record/example:8:fdrr_children_ids').should == [] # but association is
    end

    it "filters has_many records by indexed attribute values" do
      create_example(:id => '8', :name => 'John Jones',
                     :email => 'jjones@example.com', :active => 'true')
      example = Flapjack::Data::RedisRecord::Example.find_by_id('8')

      create_child(example, :id => '3', :name => 'Martin Luther King', :important => true)
      create_child(example, :id => '4', :name => 'Julius Caesar', :important => true)
      create_child(example, :id => '5', :name => 'John Smith', :important => false)

      important_kids = example.fdrr_children.intersect(:important => true).all
      important_kids.should_not be_nil
      important_kids.should be_an(Array)
      important_kids.should have(2).children
      important_kids.map(&:id).should =~ ['3', '4']
    end

  end

  context "has_sorted_set" do

    class Flapjack::Data::RedisRecord::ExampleDatum
      include Flapjack::Data::RedisRecord

      define_attributes :timestamp => :timestamp,
                        :summary => :string,
                        :emotion => :string

      belongs_to :example, :class_name => 'Flapjack::Data::RedisRecord::Example'

      index_by :emotion

      validates :timestamp, :presence => true
    end

    class Flapjack::Data::RedisRecord::Example
      has_sorted_set :fdrr_data, :class_name => 'Flapjack::Data::RedisRecord::ExampleDatum',
        :key => :timestamp
    end

    def create_datum(parent, attrs = {})
      redis.zadd("flapjack/data/redis_record/example:#{parent.id}:fdrr_data_ids", attrs[:timestamp].to_i.to_f, attrs[:id])

      redis.hmset("flapjack/data/redis_record/example_datum:#{attrs[:id]}:attrs",
                  {'summary' => attrs[:summary], 'timestamp' => attrs[:timestamp].to_i.to_f,
                   'emotion' => attrs[:emotion]}.flatten)

      redis.sadd("flapjack/data/redis_record/example_datum::by_emotion:#{attrs[:emotion]}", attrs[:id])

      redis.sadd('flapjack/data/redis_record/example_datum::ids', attrs[:id])
    end

    it "sets a parent/child has_sorted_set relationship between two records in redis" do
      create_example(:id => '8', :name => 'John Jones',
                     :email => 'jjones@example.com', :active => 'true')

      time = Time.now

      data = Flapjack::Data::RedisRecord::ExampleDatum.new(:id => '4', :timestamp => time,
        :summary => "hello!")
      data.save.should be_true

      example = Flapjack::Data::RedisRecord::Example.find_by_id('8')
      example.fdrr_data << data

      redis.keys('*').should =~ ['flapjack/data/redis_record/example::ids',
                                 'flapjack/data/redis_record/example::by_active:true',
                                 'flapjack/data/redis_record/example:8:attrs',
                                 'flapjack/data/redis_record/example:8:fdrr_data_ids',
                                 'flapjack/data/redis_record/example_datum::ids',
                                 'flapjack/data/redis_record/example_datum:4:attrs']

      redis.smembers('flapjack/data/redis_record/example_datum::ids').should == ['4']
      redis.hgetall('flapjack/data/redis_record/example_datum:4:attrs').should ==
        {'summary' => 'hello!', 'timestamp' => time.to_i.to_f.to_s}

      redis.zrange('flapjack/data/redis_record/example:8:fdrr_data_ids', 0, -1,
        :with_scores => true).should == [['4', time.to_i.to_f]]
    end

    it "loads a child from a parent's has_sorted_set relationship" do
      create_example(:id => '8', :name => 'John Jones',
                     :email => 'jjones@example.com', :active => 'true')
      example = Flapjack::Data::RedisRecord::Example.find_by_id('8')

      time = Time.now

      create_datum(example, :id => '4', :summary => 'well then', :timestamp => time)
      datum = Flapjack::Data::RedisRecord::ExampleDatum.find_by_id('4')

      data = example.fdrr_data.all

      data.should be_an(Array)
      data.should have(1).datum
      datum = data.first
      datum.should be_a(Flapjack::Data::RedisRecord::ExampleDatum)
      datum.summary.should == 'well then'
      datum.timestamp.should be_within(1).of(time) # ignore fractional differences
    end

    it "removes a parent/child has_sorted_set relationship between two records in redis" do
      create_example(:id => '8', :name => 'John Jones',
                     :email => 'jjones@example.com', :active => 'true')
      example = Flapjack::Data::RedisRecord::Example.find_by_id('8')

      time = Time.now

      create_datum(example, :id => '4', :summary => 'well then', :timestamp => time)
      datum = Flapjack::Data::RedisRecord::ExampleDatum.find_by_id('4')

      redis.smembers('flapjack/data/redis_record/example_datum::ids').should == ['4']
      redis.zrange('flapjack/data/redis_record/example:8:fdrr_data_ids', 0, -1).should == ['4']

      example.fdrr_data.delete(datum)

      redis.smembers('flapjack/data/redis_record/example_datum::ids').should == ['4']        # child not deleted
      redis.zrange('flapjack/data/redis_record/example:8:fdrr_data_ids', 0, -1).should == [] # but association is
    end

    it "filters has_sorted_set records by indexed attribute values" do
      create_example(:id => '8', :name => 'John Jones',
                     :email => 'jjones@example.com', :active => 'true')
      example = Flapjack::Data::RedisRecord::Example.find_by_id('8')

      time = Time.now

      create_datum(example, :id => '4', :summary => 'well then', :timestamp => time,
        :emotion => 'upset')
      create_datum(example, :id => '5', :summary => 'ok', :timestamp => time.to_i + 10,
        :emotion => 'happy')
      create_datum(example, :id => '6', :summary => 'aaargh', :timestamp => time.to_i + 20,
        :emotion => 'upset')

      upset_data = example.fdrr_data.intersect(:emotion => 'upset').all
      upset_data.should_not be_nil
      upset_data.should be_an(Array)
      upset_data.should have(2).children
      upset_data.map(&:id).should == ['4', '6']
    end

    it "retrieves a subset of a sorted set by index" do
      create_example(:id => '8', :name => 'John Jones',
                     :email => 'jjones@example.com', :active => 'true')
      example = Flapjack::Data::RedisRecord::Example.find_by_id('8')

      time = Time.now

      create_datum(example, :id => '4', :summary => 'well then', :timestamp => time,
        :emotion => 'upset')
      create_datum(example, :id => '5', :summary => 'ok', :timestamp => time.to_i + 10,
        :emotion => 'happy')
      create_datum(example, :id => '6', :summary => 'aaargh', :timestamp => time.to_i + 20,
        :emotion => 'upset')

      data = example.fdrr_data.intersect_range(0, 1).all
      data.should_not be_nil
      data.should be_an(Array)
      data.should have(2).children
      data.map(&:id).should == ['4', '5']
    end

    it "retrieves a reversed subset of a sorted set by index" do
      create_example(:id => '8', :name => 'John Jones',
                     :email => 'jjones@example.com', :active => 'true')
      example = Flapjack::Data::RedisRecord::Example.find_by_id('8')

      time = Time.now

      create_datum(example, :id => '4', :summary => 'well then', :timestamp => time,
        :emotion => 'upset')
      create_datum(example, :id => '5', :summary => 'ok', :timestamp => time.to_i + 10,
        :emotion => 'happy')
      create_datum(example, :id => '6', :summary => 'aaargh', :timestamp => time.to_i + 20,
        :emotion => 'upset')

      data = example.fdrr_data.intersect_range(0, 1, :order => 'desc').all
      data.should_not be_nil
      data.should be_an(Array)
      data.should have(2).children
      data.map(&:id).should == ['6', '5']
    end

    it "retrieves a subset of a sorted set by score" do
      create_example(:id => '8', :name => 'John Jones',
                     :email => 'jjones@example.com', :active => 'true')
      example = Flapjack::Data::RedisRecord::Example.find_by_id('8')

      time = Time.now

      create_datum(example, :id => '4', :summary => 'well then', :timestamp => time,
        :emotion => 'upset')
      create_datum(example, :id => '5', :summary => 'ok', :timestamp => time.to_i + 10,
        :emotion => 'happy')
      create_datum(example, :id => '6', :summary => 'aaargh', :timestamp => time.to_i + 20,
        :emotion => 'upset')

      data = example.fdrr_data.intersect_range(time.to_i - 1, time.to_i + 15, :by_score => true).all
      data.should_not be_nil
      data.should be_an(Array)
      data.should have(2).children
      data.map(&:id).should == ['4', '5']
    end

    it "retrieves a reversed subset of a sorted set by score" do
      create_example(:id => '8', :name => 'John Jones',
                     :email => 'jjones@example.com', :active => 'true')
      example = Flapjack::Data::RedisRecord::Example.find_by_id('8')

      time = Time.now

      create_datum(example, :id => '4', :summary => 'well then', :timestamp => time,
        :emotion => 'upset')
      create_datum(example, :id => '5', :summary => 'ok', :timestamp => time.to_i + 10,
        :emotion => 'happy')
      create_datum(example, :id => '6', :summary => 'aaargh', :timestamp => time.to_i + 20,
        :emotion => 'upset')

      data = example.fdrr_data.intersect_range(time.to_i - 1, time.to_i + 15,
              :order => 'desc', :by_score => true).all
      data.should_not be_nil
      data.should be_an(Array)
      data.should have(2).children
      data.map(&:id).should == ['5', '4']
    end

  end

  context "has_one" do

    class Flapjack::Data::RedisRecord::ExampleSpecial
      include Flapjack::Data::RedisRecord

      define_attributes :name => :string

      belongs_to :example, :class_name => 'Flapjack::Data::RedisRecord::Example',
        :inverse_of => :special

      validate :name, :presence => true
    end

    class Flapjack::Data::RedisRecord::Example
      has_one :special, :class_name => 'Flapjack::Data::RedisRecord::ExampleSpecial',
        :inverse_of => :example
    end

    it "sets and retrives a record via a has_one association" do
      create_example(:id => '8', :name => 'John Jones',
                     :email => 'jjones@example.com', :active => 'true')

      special = Flapjack::Data::RedisRecord::ExampleSpecial.new(:id => '22', :name => 'Bill Smith')
      special.save.should be_true

      example = Flapjack::Data::RedisRecord::Example.find_by_id('8')
      example.special = special

      redis.keys('*').should =~ ['flapjack/data/redis_record/example::ids',
                                 'flapjack/data/redis_record/example::by_active:true',
                                 'flapjack/data/redis_record/example:8:attrs',
                                 'flapjack/data/redis_record/example:8:special_id',
                                 'flapjack/data/redis_record/example_special::ids',
                                 'flapjack/data/redis_record/example_special:22:attrs',
                                 'flapjack/data/redis_record/example_special:22:belongs_to']

      redis.get('flapjack/data/redis_record/example:8:special_id').should == '22'

      redis.smembers('flapjack/data/redis_record/example_special::ids').should == ['22']
      redis.hgetall('flapjack/data/redis_record/example_special:22:attrs').should ==
        {'name' => 'Bill Smith'}

      redis.hgetall('flapjack/data/redis_record/example_special:22:belongs_to').should ==
        {'example_id' => '8'}

      example2 = Flapjack::Data::RedisRecord::Example.find_by_id('8')
      special2 = example2.special
      special2.should_not be_nil
      special2.id.should == '22'
      special2.example.id.should == '8'
    end

  end


  # TODO tests for set intersection

  # it "finds entities by tag" do
  #   entity0 = Flapjack::Data::Entity.add({'id'       => '5000',
  #                                         'name'     => 'abc-123',
  #                                         'contacts' => []})

  #   entity1 = Flapjack::Data::Entity.add({'id'       => '5001',
  #                                         'name'     => 'def-456',
  #                                         'contacts' => []})

  #   entity0.add_tags('source:foobar', 'abc')
  #   entity1.add_tags('source:foobar', 'def')

  #   entity0.should_not be_nil
  #   entity0.should be_an(Flapjack::Data::Entity)
  #   entity0.tags.should include("source:foobar")
  #   entity0.tags.should include("abc")
  #   entity0.tags.should_not include("def")
  #   entity1.should_not be_nil
  #   entity1.should be_an(Flapjack::Data::Entity)
  #   entity1.tags.should include("source:foobar")
  #   entity1.tags.should include("def")
  #   entity1.tags.should_not include("abc")

  #   entities = Flapjack::Data::Entity.find_all_with_tags(['abc'])
  #   entities.should be_an(Array)
  #   entities.should have(1).entity
  #   entities.first.should == 'abc-123'

  #   entities = Flapjack::Data::Entity.find_all_with_tags(['donkey'])
  #   entities.should be_an(Array)
  #   entities.should have(0).entities
  # end

  # it "finds entities with several tags" do
  #   entity0 = Flapjack::Data::Entity.add({'id'       => '5000',
  #                                        'name'     => 'abc-123',
  #                                        'contacts' => []})

  #   entity1 = Flapjack::Data::Entity.add({'id'       => '5001',
  #                                        'name'     => 'def-456',
  #                                        'contacts' => []})

  #   entity0.add_tags('source:foobar', 'abc')
  #   entity1.add_tags('source:foobar', 'def')

  #   entity0.should_not be_nil
  #   entity0.should be_an(Flapjack::Data::Entity)
  #   entity0.tags.should include("source:foobar")
  #   entity0.tags.should include("abc")
  #   entity1.should_not be_nil
  #   entity1.should be_an(Flapjack::Data::Entity)
  #   entity1.tags.should include("source:foobar")
  #   entity1.tags.should include("def")

  #   entities = Flapjack::Data::Entity.find_all_with_tags(['source:foobar'])
  #   entities.should be_an(Array)
  #   entities.should have(2).entity

  #   entities = Flapjack::Data::Entity.find_all_with_tags(['source:foobar', 'def'])
  #   entities.should be_an(Array)
  #   entities.should have(1).entity
  #   entities.first.should == 'def-456'
  # end

end
