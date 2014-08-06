require 'spec_helper'
require 'flapjack/data/entity'

describe Flapjack::Data::Entity, :redis => true do

  let(:name)  { 'abc-123' }
  let(:check) { 'ping' }

  it "creates an entity if allowed when it can't find it" do
    entity = Flapjack::Data::Entity.find_by_name(name, :redis => @redis, :create => true)

    expect(entity).not_to be_nil
    expect(entity.name).to eq(name)
    expect(@redis.get("entity_id:#{name}")).to match(/^\S+$/)
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
                                'contacts' => ['362']},
                                :redis => @redis)

    entity = Flapjack::Data::Entity.find_by_id('5000', :redis => @redis)
    expect(entity).not_to be_nil
    contacts = entity.contacts
    expect(contacts).not_to be_nil
    expect(contacts).to be_an(Array)
    expect(contacts).to be_empty
  end

  it "finds an entity by id" do
    Flapjack::Data::Entity.add({'id'   => '5000',
                                'name' => name},
                                :redis => @redis)

    entity = Flapjack::Data::Entity.find_by_id('5000', :redis => @redis)
    expect(entity).not_to be_nil
    expect(entity.name).to eq(name)
  end

  it "finds an entity by name" do
    Flapjack::Data::Entity.add({'id'   => '5000',
                                'name' => name},
                                :redis => @redis)

    entity = Flapjack::Data::Entity.find_by_name(name, :redis => @redis)
    expect(entity).not_to be_nil
    expect(entity.id).to eq('5000')
  end

  it "returns an empty list when asked for all entities, if there are no entities" do
    entities = Flapjack::Data::Entity.all(:redis => @redis)
    expect(entities).not_to be_nil
    expect(entities).to be_an(Array)
    expect(entities.size).to eq(0)
  end

  it "returns a list of all entities" do
    Flapjack::Data::Entity.add({'id'   => '5000',
                                'name' => name},
                                :redis => @redis)
    Flapjack::Data::Entity.add({'id'   => '5001',
                                'name' => "z_" + name},
                                :redis => @redis)

    entities = Flapjack::Data::Entity.all(:redis => @redis)
    expect(entities).not_to be_nil
    expect(entities).to be_an(Array)
    expect(entities.size).to eq(2)
    expect(entities[0].id).to eq('5000')
    expect(entities[1].id).to eq('5001')
  end

  it "returns a list of checks for an entity" do
    Flapjack::Data::Entity.add({'id'       => '5000',
                                'name'     => name},
                                :redis => @redis)

    @redis.zadd("current_checks:#{name}", Time.now.to_i, "ping")
    @redis.zadd("current_checks:#{name}", Time.now.to_i, "ssh")

    entity = Flapjack::Data::Entity.find_by_name(name, :redis => @redis)
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
                                'contacts' => []},
                               :redis => @redis)

    @redis.zadd("current_checks:#{name}", Time.now.to_i, "ping")
    @redis.zadd("current_checks:#{name}", Time.now.to_i, "ssh")

    entity = Flapjack::Data::Entity.find_by_id(5000, :redis => @redis)
    check_count = entity.check_count
    expect(check_count).not_to be_nil
    expect(check_count).to eq(2)
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
    expect(entities).not_to be_nil
    expect(entities).to be_an(Array)
    expect(entities.size).to eq(1)
    expect(entities.first).to eq('abc-123')
  end

  it "adds tags to entities" do
    entity = Flapjack::Data::Entity.add({'id'       => '5000',
                                         'name'     => 'abc-123',
                                         'contacts' => []},
                                        :redis => @redis)

    entity.add_tags('source:foobar', 'foo')

    expect(entity).not_to be_nil
    expect(entity).to be_an(Flapjack::Data::Entity)
    expect(entity.name).to eq('abc-123')
    expect(entity.tags).to include("source:foobar")
    expect(entity.tags).to include("foo")

    # and test the tags as read back from redis
    entity = Flapjack::Data::Entity.find_by_id('5000', :redis => @redis)
    expect(entity.tags).to include("source:foobar")
    expect(entity.tags).to include("foo")

  end

  it "deletes tags from entities" do
    entity = Flapjack::Data::Entity.add({'id'       => '5000',
                                         'name'     => 'abc-123',
                                         'contacts' => []},
                                        :redis => @redis)

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
                                          'contacts' => []},
                                         :redis => @redis)

    entity1 = Flapjack::Data::Entity.add({'id'       => '5001',
                                          'name'     => 'def-456',
                                          'contacts' => []},
                                         :redis => @redis)

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

    entities = Flapjack::Data::Entity.find_all_with_tags(['abc'], :redis => @redis)
    expect(entities).to be_an(Array)
    expect(entities.size).to eq(1)
    expect(entities.first).to eq('abc-123')

    entities = Flapjack::Data::Entity.find_all_with_tags(['donkey'], :redis => @redis)
    expect(entities).to be_an(Array)
    expect(entities).to be_empty
  end

  it "finds entities with several tags" do
    entity0 = Flapjack::Data::Entity.add({'id'       => '5000',
                                         'name'     => 'abc-123',
                                         'contacts' => []},
                                        :redis => @redis)

    entity1 = Flapjack::Data::Entity.add({'id'       => '5001',
                                         'name'     => 'def-456',
                                         'contacts' => []},
                                        :redis => @redis)

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

    entities = Flapjack::Data::Entity.find_all_with_tags(['source:foobar'], :redis => @redis)
    expect(entities).to be_an(Array)
    expect(entities.size).to eq(2)

    entities = Flapjack::Data::Entity.find_all_with_tags(['source:foobar', 'def'], :redis => @redis)
    expect(entities).to be_an(Array)
    expect(entities.size).to eq(1)
    expect(entities.first).to eq('def-456')
  end

  context 'entity renaming' do

    def do_rename
      Flapjack::Data::Entity.add({'id'   => '5000',
                                  'name' => 'name2',
                                  'contacts' => ['362']},
                                  :redis => @redis)
    end

    let(:time_i) { Time.now.to_i }

    let(:sha1) { Digest::SHA1.new }
    let(:hash_name1) { Digest.hexencode(sha1.digest('name1:PING'))[0..7].downcase }
    let(:hash_name2) { Digest.hexencode(sha1.digest('name2:PING'))[0..7].downcase }

    before(:each) do
      Flapjack::Data::Contact.add({'id'         => '362',
                                   'first_name' => 'John',
                                   'last_name'  => 'Johnson',
                                   'email'      => 'johnj@example.com' },
                                   :redis       => @redis)

      Flapjack::Data::Entity.add({'id'   => '5000',
                                  'name' => 'name1',
                                  'contacts' => ['362']},
                                  :redis => @redis)
    end

    it 'renames the entity name to id lookup and the name in the entity hash by id' do
      expect(@redis.get('entity_id:name1')).to eq('5000')
      expect(@redis.hget('entity:5000', 'name')).to eq('name1')

      do_rename

      expect(@redis.get('entity_id:name1')).to be_nil
      expect(@redis.get('entity_id:name2')).to eq('5000')
      expect(@redis.hget('entity:5000', 'name')).to eq('name2')
    end

    it 'does not rename an entity of an entity with the new name already exists' do
      Flapjack::Data::Entity.add({'id'   => '5001',
                                  'name' => 'name2',
                                  'contacts' => []},
                                  :redis => @redis)

      expect(@redis.get('entity_id:name1')).to eq('5000')
      expect(@redis.hget('entity:5000', 'name')).to eq('name1')
      expect(@redis.get('entity_id:name2')).to eq('5001')
      expect(@redis.hget('entity:5001', 'name')).to eq('name2')

      do_rename

      # no change
      expect(@redis.get('entity_id:name1')).to eq('5000')
      expect(@redis.hget('entity:5000', 'name')).to eq('name1')
      expect(@redis.get('entity_id:name2')).to eq('5001')
      expect(@redis.hget('entity:5001', 'name')).to eq('name2')
    end

    it 'renames current check state' do
      data = {'state' => 'critical', 'last_change' => time_i.to_s, 'last_update' => time_i.to_s}
      @redis.mapped_hmset('check:name1:PING', data)

      do_rename

      expect(@redis.hgetall('check:name1:PING')).to eq({})
      expect(@redis.hgetall('check:name2:PING')).to eq(data)
    end

    it 'renames stored check state changes' do
      @redis.lpush('name1:PING:states', time_i)
      @redis.set("name1:PING:#{time_i}:state", 'critical')
      @redis.set("name1:PING:#{time_i}:summary", 'bad')
      @redis.zadd('name1:PING:sorted_state_timestamps', time_i, time_i)

      do_rename

      expect(@redis.type('name1:PING:states')).to eq('none')
      expect(@redis.type('name2:PING:states')).to eq('list')
      expect(@redis.lindex('name2:PING:states', 0)).to eq(time_i.to_s)
      expect(@redis.get("name1:PING:#{time_i}:state")).to be_nil
      expect(@redis.get("name2:PING:#{time_i}:state")).to eq('critical')
      expect(@redis.get("name1:PING:#{time_i}:summary")).to be_nil
      expect(@redis.get("name2:PING:#{time_i}:summary")).to eq('bad')
      expect(@redis.zrange("name1:PING:sorted_state_timestamps", 0, -1, :with_scores => true)).to eq([])
      expect(@redis.zrange("name2:PING:sorted_state_timestamps", 0, -1, :with_scores => true)).to eq([[time_i.to_s, time_i.to_f]])
    end

    it 'renames stored action events' do
      @redis.hset('name1:PING:actions', time_i.to_s, 'acknowledgement')

      do_rename

      expect(@redis.hget('name1:PING:actions', time_i.to_s)).to be_nil
      expect(@redis.hget('name2:PING:actions', time_i.to_s)).to eq('acknowledgement')
    end

    it 'renames entries in the sorted set of failing checks' do
      data = {'state' => 'critical', 'last_change' => time_i.to_s, 'last_update' => time_i.to_s}
      @redis.mapped_hmset('check:name1:PING', data)

      @redis.zadd('failed_checks', time_i, 'name1:PING')

      do_rename

      expect(@redis.zrange('failed_checks', 0, -1, :with_scores => true)).to eq([['name2:PING', time_i.to_f]])
    end

    it 'renames the list of current checks, and its entries' do
      @redis.zadd('current_checks:name1', time_i, 'PING')

      do_rename

      expect(@redis.zrange('current_checks:name1', 0, -1, :with_scores => true)).to eq([])
      expect(@redis.zrange('current_checks:name2', 0, -1, :with_scores => true)).to eq([['PING', time_i.to_f]])
    end

    it 'renames an entry in the list of current entities' do
      @redis.zadd('current_entities', time_i, 'name1')

      do_rename

      expect(@redis.zrange('current_entities', 0, -1, :with_scores => true)).to eq([['name2', time_i.to_f]])
    end

    it 'renames a current unscheduled maintenance key' do
      @redis.setex('name1:PING:unscheduled_maintenance', 30000, time_i)

      do_rename

      expect(@redis.get('name1:PING:unscheduled_maintenance')).to be_nil
      expect(@redis.get('name2:PING:unscheduled_maintenance')).to eq(time_i.to_s)
      expect(@redis.ttl('name2:PING:unscheduled_maintenance')).to be <= 30000
    end

    it 'renames stored unscheduled maintenance periods and sorted timestamps' do
      @redis.zadd('name1:PING:unscheduled_maintenances', 30000, time_i)
      @redis.set("name1:PING:#{time_i}:unscheduled_maintenance:summary", 'really bad')
      @redis.zadd('name1:PING:sorted_unscheduled_maintenance_timestamps', time_i, time_i)

      do_rename

      expect(@redis.zrange('name1:PING:unscheduled_maintenances', 0, -1, :with_scores => true)).to eq([])
      expect(@redis.zrange('name2:PING:unscheduled_maintenances', 0, -1, :with_scores => true)).to eq([[time_i.to_s, 30000.0]])
      expect(@redis.get("name1:PING:#{time_i}:unscheduled_maintenance:summary")).to be_nil
      expect(@redis.get("name2:PING:#{time_i}:unscheduled_maintenance:summary")).to eq('really bad')
      expect(@redis.zrange('name1:PING:sorted_unscheduled_maintenance_timestamps', 0, -1, :with_scores => true)).to eq([])
      expect(@redis.zrange('name2:PING:sorted_unscheduled_maintenance_timestamps', 0, -1, :with_scores => true)).to eq([[time_i.to_s, time_i.to_f]])
    end

    it 'renames a current scheduled maintenance key' do
      @redis.setex('name1:PING:scheduled_maintenance', 30000, time_i)

      do_rename

      expect(@redis.get('name1:PING:scheduled_maintenance')).to be_nil
      expect(@redis.get('name2:PING:scheduled_maintenance')).to eq(time_i.to_s)
      expect(@redis.ttl('name2:PING:scheduled_maintenance')).to be <= 30000
    end

    it 'renames stored scheduled maintenance periods and sorted timestamps' do
      @redis.zadd('name1:PING:scheduled_maintenances', 30000, time_i)
      @redis.set("name1:PING:#{time_i}:scheduled_maintenance:summary", 'really bad')
      @redis.zadd('name1:PING:sorted_scheduled_maintenance_timestamps', time_i, time_i)

      do_rename

      expect(@redis.zrange('name1:PING:scheduled_maintenances', 0, -1, :with_scores => true)).to eq([])
      expect(@redis.zrange('name2:PING:scheduled_maintenances', 0, -1, :with_scores => true)).to eq([[time_i.to_s, 30000.0]])
      expect(@redis.get("name1:PING:#{time_i}:scheduled_maintenance:summary")).to be_nil
      expect(@redis.get("name2:PING:#{time_i}:scheduled_maintenance:summary")).to eq('really bad')
      expect(@redis.zrange('name1:PING:sorted_scheduled_maintenance_timestamps', 0, -1, :with_scores => true)).to eq([])
      expect(@redis.zrange('name2:PING:sorted_scheduled_maintenance_timestamps', 0, -1, :with_scores => true)).to eq([[time_i.to_s, time_i.to_f]])
    end

    it 'renames current notifications' do
      @redis.set('name1:PING:last_problem_notification',         time_i)
      @redis.set('name1:PING:last_unknown_notification',         time_i - 100)
      @redis.set('name1:PING:last_warning_notification',         time_i - 50)
      @redis.set('name1:PING:last_critical_notification',        time_i)
      @redis.set('name1:PING:last_recovery_notification',        time_i - 200)
      @redis.set('name1:PING:last_acknowledgement_notification', time_i - 250)

      do_rename

      expect(@redis.get('name1:PING:last_problem_notification')).to be_nil
      expect(@redis.get('name1:PING:last_unknown_notification')).to be_nil
      expect(@redis.get('name1:PING:last_warning_notification')).to be_nil
      expect(@redis.get('name1:PING:last_critical_notification')).to be_nil
      expect(@redis.get('name1:PING:last_recovery_notification')).to be_nil
      expect(@redis.get('name1:PING:last_acknowledgement_notification')).to be_nil
      expect(@redis.get('name2:PING:last_problem_notification')).to eq(time_i.to_s)
      expect(@redis.get('name2:PING:last_unknown_notification')).to eq((time_i - 100).to_s)
      expect(@redis.get('name2:PING:last_warning_notification')).to eq((time_i - 50).to_s)
      expect(@redis.get('name2:PING:last_critical_notification')).to eq(time_i.to_s)
      expect(@redis.get('name2:PING:last_recovery_notification')).to eq((time_i - 200).to_s)
      expect(@redis.get('name2:PING:last_acknowledgement_notification')).to eq((time_i - 250).to_s)
    end

    it 'renames stored notifications' do
      @redis.lpush('name1:PING:problem_notifications', time_i)
      @redis.lpush('name1:PING:unknown_notifications', time_i - 100)
      @redis.lpush('name1:PING:warning_notifications', time_i - 50)
      @redis.lpush('name1:PING:critical_notifications', time_i)
      @redis.lpush('name1:PING:recovery_notifications', time_i - 200)
      @redis.lpush('name1:PING:acknowledgement_notifications', time_i - 250)

      do_rename

      expect(@redis.lindex('name1:PING:problem_notifications', 0)).to be_nil
      expect(@redis.lindex('name1:PING:unknown_notifications', 0)).to be_nil
      expect(@redis.lindex('name1:PING:warning_notifications', 0)).to be_nil
      expect(@redis.lindex('name1:PING:critical_notifications', 0)).to be_nil
      expect(@redis.lindex('name1:PING:recovery_notifications', 0)).to be_nil
      expect(@redis.lindex('name1:PING:acknowledgement_notifications', 0)).to be_nil
      expect(@redis.lindex('name2:PING:problem_notifications', 0)).to eq(time_i.to_s)
      expect(@redis.lindex('name2:PING:unknown_notifications', 0)).to eq((time_i - 100).to_s)
      expect(@redis.lindex('name2:PING:warning_notifications', 0)).to eq((time_i - 50).to_s)
      expect(@redis.lindex('name2:PING:critical_notifications', 0)).to eq(time_i.to_s)
      expect(@redis.lindex('name2:PING:recovery_notifications', 0)).to eq((time_i - 200).to_s)
      expect(@redis.lindex('name2:PING:acknowledgement_notifications', 0)).to eq((time_i - 250).to_s)
    end

    it 'renames alert blocks' do
      @redis.setex('drop_alerts_for_contact:362:email:name1:PING:critical', 30000, 30000)

      do_rename

      expect(@redis.get('drop_alerts_for_contact:362:email:name1:PING:critical')).to be_nil
      expect(@redis.get('drop_alerts_for_contact:362:email:name2:PING:critical')).to eq(30000.to_s)
      expect(@redis.ttl('drop_alerts_for_contact:362:email:name2:PING:critical')).to be <= 30000
    end

    it "updates the check hash set" do
      data = {'state' => 'critical', 'last_change' => time_i.to_s, 'last_update' => time_i.to_s}
      @redis.mapped_hmset('check:name1:PING', data)

      @redis.hset('checks_by_hash', hash_name1, 'name1:PING')

      do_rename

      expect(@redis.hget('checks_by_hash', hash_name1)).to be_nil
      expect(@redis.hget('checks_by_hash', hash_name2)).to eq('name2:PING')
    end

    # # Not a good idea, really

    # it 'renames the event_id within in-flight notifications' do

    #   data = {'event_id'       => 'name1:PING',
    #           'event_hash'     => hash_name1,
    #           'state'          => 'critical',
    #           'summary'        => 'quite bad',
    #           'details'        => 'not really bad',
    #           'time'           => time_i,
    #           'duration'       => nil,
    #           'count'          => 50000,
    #           'last_state'     => 'ok',
    #           'last_summary'   => 'good',
    #           'state_duration' => 30,
    #           'type'           => 'problem',
    #           'severity'       => 'critical',
    #           'tags'           => ['name1', 'PING'] }

    #   @redis.lpush('notifications', data.to_json)

    #   do_rename

    #   name2_data = data.merge('event_id'   => 'name2:PING',
    #                           'event_hash' => hash_name2,
    #                           'tags'       => ['name2', 'PING'])

    #   notif = @redis.lindex('notifications', 0)
    #   expect(notif).not_to be_nil
    #   expect(JSON.parse(notif)).to eq(name2_data)
    # end

    # it 'renames checks within in-flight alerts' do
    #   data = {'media'               => 'email',
    #           'address'             => 'johnj@example.com',
    #           'contact_id'          => '362',
    #           'contact_first_name'  => 'John',
    #           'contact_last_name'   => 'Johnson',
    #           'event_id'            => 'name1:PING',
    #           'event_hash'          => hash_name1,
    #           'summary'             => '100% packet loss',
    #           'duration'            => nil,
    #           'last_state'          => 'ok',
    #           'last_summary'        => 'ok now',
    #           'state_duration'      => 30,
    #           'details'             => 'hmmm',
    #           'time'                => time_i,
    #           'notification_type'   =>'problem',
    #           'event_count'         => 3,
    #           'tags'                => ['name1', 'PING']}

    #   @redis.lpush('email_notifications', data.to_json)

    #   do_rename

    #   name2_data = data.merge('event_id'   => 'name2:PING',
    #                           'event_hash' => hash_name2,
    #                           'tags'       => ['name2', 'PING'])

    #   notif = @redis.lindex('email_notifications', 0)
    #   expect(notif).not_to be_nil
    #   expect(JSON.parse(notif)).to eq(name2_data)
    # end

    it 'renames entries within alerting checks' do
      data = {'state' => 'critical', 'last_change' => time_i.to_s, 'last_update' => time_i.to_s}
      @redis.mapped_hmset('check:name1:PING', data)

      @redis.zadd('contact_alerting_checks:362:media:email', time_i, 'name1:PING')

      do_rename

      expect(@redis.zrange('contact_alerting_checks:362:media:email', 0, -1, :with_scores => true)).to eq(
        [['name2:PING', time_i.to_f]]
      )
    end

  end

end
