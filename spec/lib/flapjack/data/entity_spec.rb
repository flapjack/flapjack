require 'spec_helper'
require 'flapjack/data/entity'

describe Flapjack::Data::Entity, :redis => true do

  let(:name)  { 'abc-123' }
  let(:check) { 'ping' }

  it "creates an entity if allowed when it can't find it" do
    entity = Flapjack::Data::Entity.find_by_name(name, :redis => @redis, :create => true)

    expect(entity).not_to be_nil
    expect(entity.name).to eq(name)
    expect(@redis.hget('all_entity_ids_by_name', name)).to match(/^\S+$/)
  end

  it 'creates tags if passed when added' do
    Flapjack::Data::Entity.add({'id'   => '5000',
                                'name' => name,
                                'tags' => ['database', 'virtual']},
                                :redis => @redis)

    entity = Flapjack::Data::Entity.find_by_id('5000', :redis => @redis)
    expect(entity).not_to be_nil
    expect(entity.tags).to eq(Set.new(['database', 'virtual']))
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

  context 'renaming and merging' do

    let(:time_i) { Time.now.to_i }

    let(:sha1) { Digest::SHA1.new }
    let(:hash_name1) { Digest.hexencode(sha1.digest('name1:PING'))[0..7].downcase }
    let(:hash_name2) { Digest.hexencode(sha1.digest('name2:PING'))[0..7].downcase }

    def add_name1
      Flapjack::Data::Entity.add({'id'   => '5000',
                                  'name' => 'name1',
                                  'contacts' => ['362']},
                                  :redis => @redis)
    end

    def add_name2
      Flapjack::Data::Entity.add({'id'   => '5000',
                                  'name' => 'name2',
                                  'contacts' => ['362']},
                                  :redis => @redis)
    end

    before(:each) do
      Flapjack::Data::Contact.add({'id'         => '362',
                                   'first_name' => 'John',
                                   'last_name'  => 'Johnson',
                                   'email'      => 'johnj@example.com' },
                                   :redis       => @redis)
    end

    context 'check that rename and merge are called by add'

    context 'entity renaming on #add' do

      let(:time_i) { Time.now.to_i }

      let(:sha1) { Digest::SHA1.new }
      let(:hash_name1) { Digest.hexencode(sha1.digest('name1:PING'))[0..7].downcase }
      let(:hash_name2) { Digest.hexencode(sha1.digest('name2:PING'))[0..7].downcase }

      before(:each) do
        add_name1
      end

      it 'renames the "entity name to id lookup" and the name in the "entity hash by id"' do
        expect(@redis.hget('all_entity_ids_by_name', 'name1')).to eq('5000')
        expect(@redis.hget('all_entity_names_by_id', '5000')).to eq('name1')

        add_name2

        expect(@redis.hget('all_entity_ids_by_name', 'name1')).to be_nil
        expect(@redis.hget('all_entity_ids_by_name', 'name2')).to eq('5000')
        expect(@redis.hget('all_entity_names_by_id', '5000')).to eq('name2')
      end

      it 'does not rename an entity if an entity with the new name already exists' do
        Flapjack::Data::Entity.add({'id'   => '5001',
                                    'name' => 'name2',
                                    'contacts' => []},
                                    :redis => @redis)

        expect(@redis.hget('all_entity_ids_by_name', 'name1')).to eq('5000')
        expect(@redis.hget('all_entity_names_by_id', '5000')).to eq('name1')
        expect(@redis.hget('all_entity_ids_by_name', 'name2')).to eq('5001')
        expect(@redis.hget('all_entity_names_by_id', '5001')).to eq('name2')

        add_name2

        # no change
        expect(@redis.hget('all_entity_ids_by_name', 'name1')).to eq('5000')
        expect(@redis.hget('all_entity_names_by_id', '5000')).to eq('name1')
        expect(@redis.hget('all_entity_ids_by_name', 'name2')).to eq('5001')
        expect(@redis.hget('all_entity_names_by_id', '5001')).to eq('name2')
      end

      it 'renames current check state' do
        data = {'state' => 'critical', 'last_change' => time_i.to_s, 'last_update' => time_i.to_s}
        @redis.mapped_hmset('check:name1:PING', data)

        add_name2

        expect(@redis.hgetall('check:name1:PING')).to eq({})
        expect(@redis.hgetall('check:name2:PING')).to eq(data)
      end

      it 'renames stored check state changes' do
        @redis.rpush('name1:PING:states', time_i)
        @redis.set("name1:PING:#{time_i}:state", 'critical')
        @redis.set("name1:PING:#{time_i}:summary", 'bad')
        @redis.zadd('name1:PING:sorted_state_timestamps', time_i, time_i)

        add_name2

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

        add_name2

        expect(@redis.hget('name1:PING:actions', time_i.to_s)).to be_nil
        expect(@redis.hget('name2:PING:actions', time_i.to_s)).to eq('acknowledgement')
      end

      it 'renames entries in the sorted set of failing checks' do
        data = {'state' => 'critical', 'last_change' => time_i.to_s, 'last_update' => time_i.to_s}
        @redis.mapped_hmset('check:name1:PING', data)

        @redis.zadd('failed_checks', time_i, 'name1:PING')

        add_name2

        expect(@redis.zrange('failed_checks', 0, -1, :with_scores => true)).to eq([['name2:PING', time_i.to_f]])
      end

      it 'renames the list of current checks, and its entries' do
        @redis.zadd('current_checks:name1', time_i, 'PING')

        add_name2

        expect(@redis.zrange('current_checks:name1', 0, -1, :with_scores => true)).to eq([])
        expect(@redis.zrange('current_checks:name2', 0, -1, :with_scores => true)).to eq([['PING', time_i.to_f]])
      end

      it 'renames an entry in the list of current entities' do
        @redis.zadd('current_entities', time_i, 'name1')

        add_name2

        expect(@redis.zrange('current_entities', 0, -1, :with_scores => true)).to eq([['name2', time_i.to_f]])
      end

      it 'renames a current unscheduled maintenance key' do
        @redis.setex('name1:PING:unscheduled_maintenance', 30, time_i)

        add_name2

        expect(@redis.get('name1:PING:unscheduled_maintenance')).to be_nil
        expect(@redis.get('name2:PING:unscheduled_maintenance')).to eq(time_i.to_s)
        expect(@redis.ttl('name2:PING:unscheduled_maintenance')).to be <= 30
      end

      it 'renames stored unscheduled maintenance periods and sorted timestamps' do
        @redis.zadd('name1:PING:unscheduled_maintenances', 30, time_i)
        @redis.set("name1:PING:#{time_i}:unscheduled_maintenance:summary", 'really bad')
        @redis.zadd('name1:PING:sorted_unscheduled_maintenance_timestamps', time_i, time_i)

        add_name2

        expect(@redis.zrange('name1:PING:unscheduled_maintenances', 0, -1, :with_scores => true)).to eq([])
        expect(@redis.zrange('name2:PING:unscheduled_maintenances', 0, -1, :with_scores => true)).to eq([[time_i.to_s, 30.0]])
        expect(@redis.get("name1:PING:#{time_i}:unscheduled_maintenance:summary")).to be_nil
        expect(@redis.get("name2:PING:#{time_i}:unscheduled_maintenance:summary")).to eq('really bad')
        expect(@redis.zrange('name1:PING:sorted_unscheduled_maintenance_timestamps', 0, -1, :with_scores => true)).to eq([])
        expect(@redis.zrange('name2:PING:sorted_unscheduled_maintenance_timestamps', 0, -1, :with_scores => true)).to eq([[time_i.to_s, time_i.to_f]])
      end

      it 'renames a current scheduled maintenance key' do
        @redis.setex('name1:PING:scheduled_maintenance', 30, time_i)

        add_name2

        expect(@redis.get('name1:PING:scheduled_maintenance')).to be_nil
        expect(@redis.get('name2:PING:scheduled_maintenance')).to eq(time_i.to_s)
        expect(@redis.ttl('name2:PING:scheduled_maintenance')).to be <= 30
      end

      it 'renames stored scheduled maintenance periods and sorted timestamps' do
        @redis.zadd('name1:PING:scheduled_maintenances', 30, time_i)
        @redis.set("name1:PING:#{time_i}:scheduled_maintenance:summary", 'really bad')
        @redis.zadd('name1:PING:sorted_scheduled_maintenance_timestamps', time_i, time_i)

        add_name2

        expect(@redis.zrange('name1:PING:scheduled_maintenances', 0, -1, :with_scores => true)).to eq([])
        expect(@redis.zrange('name2:PING:scheduled_maintenances', 0, -1, :with_scores => true)).to eq([[time_i.to_s, 30.0]])
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

        add_name2

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

        add_name2

        expect(@redis.llen('name1:PING:problem_notifications')).to eq(0)
        expect(@redis.llen('name1:PING:unknown_notifications')).to eq(0)
        expect(@redis.llen('name1:PING:warning_notifications')).to eq(0)
        expect(@redis.llen('name1:PING:critical_notifications')).to eq(0)
        expect(@redis.llen('name1:PING:recovery_notifications')).to eq(0)
        expect(@redis.llen('name1:PING:acknowledgement_notifications')).to eq(0)
        expect(@redis.lindex('name2:PING:problem_notifications', 0)).to eq(time_i.to_s)
        expect(@redis.lindex('name2:PING:unknown_notifications', 0)).to eq((time_i - 100).to_s)
        expect(@redis.lindex('name2:PING:warning_notifications', 0)).to eq((time_i - 50).to_s)
        expect(@redis.lindex('name2:PING:critical_notifications', 0)).to eq(time_i.to_s)
        expect(@redis.lindex('name2:PING:recovery_notifications', 0)).to eq((time_i - 200).to_s)
        expect(@redis.lindex('name2:PING:acknowledgement_notifications', 0)).to eq((time_i - 250).to_s)
      end

      it 'renames alert blocks' do
        @redis.setex('drop_alerts_for_contact:362:email:name1:PING:critical', 30, 30)

        add_name2

        expect(@redis.get('drop_alerts_for_contact:362:email:name1:PING:critical')).to be_nil
        expect(@redis.get('drop_alerts_for_contact:362:email:name2:PING:critical')).to eq(30.to_s)
        expect(@redis.ttl('drop_alerts_for_contact:362:email:name2:PING:critical')).to be <= 30
      end

      it "updates the check hash set" do
        data = {'state' => 'critical', 'last_change' => time_i.to_s, 'last_update' => time_i.to_s}
        @redis.mapped_hmset('check:name1:PING', data)

        @redis.hset('checks_by_hash', hash_name1, 'name1:PING')

        add_name2

        expect(@redis.hget('checks_by_hash', hash_name1)).to be_nil
        expect(@redis.hget('checks_by_hash', hash_name2)).to eq('name2:PING')
      end

      it 'renames entries within alerting checks' do
        data = {'state' => 'critical', 'last_change' => time_i.to_s, 'last_update' => time_i.to_s}
        @redis.mapped_hmset('check:name1:PING', data)

        @redis.zadd('contact_alerting_checks:362:media:email', time_i, 'name1:PING')

        add_name2

        expect(@redis.zrange('contact_alerting_checks:362:media:email', 0, -1, :with_scores => true)).to eq(
          [['name2:PING', time_i.to_f]]
        )
      end

    end

    context 'entity merging' do

      let(:time_2_i) { time_i + 30 }

      def do_merge
        Flapjack::Data::Entity.merge('name1', 'name2', :redis => @redis)
      end

      # used as basic existence check for state on check on original entity
      def add_state1
        data = {'state' => 'critical', 'last_change' => time_i.to_s, 'last_update' => time_i.to_s}
        @redis.mapped_hmset('check:name1:PING', data)
      end

      def add_state2
        data = {'state' => 'critical', 'last_change' => time_2_i.to_s, 'last_update' => time_2_i.to_s}
        @redis.mapped_hmset('check:name2:PING', data)
      end

      before(:each) do
        add_name2
      end

      it 'clears the old id when a name exists' do
        expect(@redis.hget('all_entity_ids_by_name', 'name2')).to eq('5000')
        expect(@redis.hget('all_entity_names_by_id', '5000')).to eq('name2')

        Flapjack::Data::Entity.add({'id'   => '5001',
                                    'name' => 'name2'},
                                    :redis => @redis)

        expect(@redis.hget('all_entity_ids_by_name', 'name2')).to eq('5001')
        expect(@redis.hget('all_entity_names_by_id', '5000')).to be_nil
        expect(@redis.hget('all_entity_names_by_id', '5001')).to eq('name2')
      end

      it 'does not overwrite current state for a check' do
        add_state1
        data_2 = {'state' => 'critical', 'last_change' => time_2_i.to_s, 'last_update' => time_2_i.to_s}
        @redis.mapped_hmset('check:name2:PING', data_2)

        do_merge

        expect(@redis.hgetall('check:name1:PING')).to eq({})
        expect(@redis.hgetall('check:name2:PING')).to eq(data_2)
      end

      it 'sets current state for a check if no new state is set' do
        data = {'state' => 'critical', 'last_change' => time_i.to_s, 'last_update' => time_i.to_s}
        @redis.mapped_hmset('check:name1:PING', data)

        do_merge

        expect(@redis.hgetall('check:name1:PING')).to eq({})
        expect(@redis.hgetall('check:name2:PING')).to eq(data)
      end

      it 'merges stored check state changes' do
        add_state1
        add_state2

        @redis.rpush('name1:PING:states', time_i)
        @redis.set("name1:PING:#{time_i}:state", 'critical')
        @redis.set("name1:PING:#{time_i}:summary", 'bad')
        @redis.zadd('name1:PING:sorted_state_timestamps', time_i, time_i)

        @redis.rpush('name2:PING:states', time_2_i)
        @redis.set("name2:PING:#{time_2_i}:state", 'ok')
        @redis.set("name2:PING:#{time_2_i}:summary", 'good')
        @redis.zadd('name2:PING:sorted_state_timestamps', time_2_i, time_2_i)

        do_merge

        expect(@redis.type('name1:PING:states')).to eq('none')
        expect(@redis.type('name2:PING:states')).to eq('list')

        expect(@redis.llen('name2:PING:states')).to eq(2)
        expect(@redis.lindex('name2:PING:states', 0)).to eq(time_i.to_s)
        expect(@redis.lindex('name2:PING:states', 1)).to eq(time_2_i.to_s)

        expect(@redis.get("name1:PING:#{time_i}:state")).to be_nil
        expect(@redis.get("name2:PING:#{time_i}:state")).to eq('critical')
        expect(@redis.get("name2:PING:#{time_2_i}:state")).to eq('ok')

        expect(@redis.get("name1:PING:#{time_i}:summary")).to be_nil
        expect(@redis.get("name2:PING:#{time_i}:summary")).to eq('bad')
        expect(@redis.get("name2:PING:#{time_2_i}:summary")).to eq('good')

        expect(@redis.zrange("name1:PING:sorted_state_timestamps", 0, -1, :with_scores => true)).to eq(
          [])
        expect(@redis.zrange("name2:PING:sorted_state_timestamps", 0, -1, :with_scores => true)).to eq(
          [[time_i.to_s, time_i.to_f], [time_2_i.to_s, time_2_i.to_f]])
      end

      it 'merges stored action events' do
        @redis.hset('name1:PING:actions', time_i, 'acknowledgement')
        @redis.hset('name2:PING:actions', time_2_i, 'test_notifications')

        do_merge

        expect(@redis.hget('name1:PING:actions', time_i.to_s)).to be_nil
        expect(@redis.hget('name2:PING:actions', time_i.to_s)).to eq('acknowledgement')
        expect(@redis.hget('name2:PING:actions', time_2_i.to_s)).to eq('test_notifications')
      end

      it 'does not overwrite an entry in the sorted set of failing checks' do
        add_state1
        add_state2

        @redis.zadd('failed_checks', time_i,   'name1:PING')
        @redis.zadd('failed_checks', time_2_i, 'name2:PING')

        do_merge

        expect(@redis.zrange('failed_checks', 0, -1, :with_scores => true)).to eq([['name2:PING', time_2_i.to_f]])
      end

      it 'merges an entry in the sorted set of failing checks (if no new state data)' do
        add_state1

        @redis.zadd('failed_checks', time_i, 'name1:PING')

        do_merge

        expect(@redis.zrange('failed_checks', 0, -1, :with_scores => true)).to eq([['name2:PING', time_i.to_f]])
      end

      it 'merges the list of current checks, and its entries' do
        @redis.zadd('current_checks:name1', time_i, 'PING')
        @redis.zadd('current_checks:name2', time_2_i, 'SSH')

        do_merge

        expect(@redis.zrange('current_checks:name1', 0, -1, :with_scores => true)).to eq(
          [])
        expect(@redis.zrange('current_checks:name2', 0, -1, :with_scores => true)).to eq(
          [['PING', time_i.to_f], ['SSH', time_2_i.to_f]])
      end

      it 'removes an entry from the list of current entities' do
        @redis.zadd('current_entities', time_i, 'name1')
        @redis.zadd('current_entities', time_2_i, 'name2')

        do_merge

        expect(@redis.zrange('current_entities', 0, -1, :with_scores => true)).to eq([['name2', time_2_i.to_f]])
      end

      it 'moves an entry within the list of current entities' do
        @redis.zadd('current_entities', time_i, 'name1')

        do_merge

        expect(@redis.zrange('current_entities', 0, -1, :with_scores => true)).to eq([['name2', time_i.to_f]])
      end

      it "renames an unscheduled maintenance key" do
        @redis.setex('name1:PING:unscheduled_maintenance', 30, time_i)
        @redis.zadd('name1:PING:unscheduled_maintenances', 30, time_i)

        do_merge

        expect(@redis.get('name1:PING:unscheduled_maintenance')).to be_nil
        expect(@redis.get('name2:PING:unscheduled_maintenance')).to eq(time_i.to_s)
        expect(@redis.ttl('name2:PING:unscheduled_maintenance')).to be <= 30
      end

      it 'merges an unscheduled maintenance key (older has longest to live)' do
        @redis.setex('name1:PING:unscheduled_maintenance', 60, time_i)
        @redis.zadd('name1:PING:unscheduled_maintenances', 60, time_i)
        @redis.setex('name2:PING:unscheduled_maintenance', 20, time_2_i)
        @redis.zadd('name2:PING:unscheduled_maintenances', 20, time_2_i)

        do_merge

        expect(@redis.get('name1:PING:unscheduled_maintenance')).to be_nil
        expect(@redis.get('name2:PING:unscheduled_maintenance')).to eq(time_i.to_s)
        expect(@redis.ttl('name2:PING:unscheduled_maintenance')).to be <= 60
      end

      it 'merges an unscheduled maintenance key (newer has longest to live)' do
        @redis.setex('name1:PING:unscheduled_maintenance', 40, time_i)
        @redis.zadd('name1:PING:unscheduled_maintenances', 40, time_i)
        @redis.setex('name2:PING:unscheduled_maintenance', 20, time_2_i)
        @redis.zadd('name2:PING:unscheduled_maintenances', 20, time_i)

        do_merge

        expect(@redis.get('name1:PING:unscheduled_maintenance')).to be_nil
        expect(@redis.get('name2:PING:unscheduled_maintenance')).to eq(time_2_i.to_s)
        expect(@redis.ttl('name2:PING:unscheduled_maintenance')).to be <= 20
      end

      it 'merges stored unscheduled maintenance periods and sorted timestamps' do
        @redis.zadd('name1:PING:unscheduled_maintenances', 30, time_i)
        @redis.set("name1:PING:#{time_i}:unscheduled_maintenance:summary", 'really bad')
        @redis.zadd('name1:PING:sorted_unscheduled_maintenance_timestamps', time_i, time_i)

        @redis.zadd('name2:PING:unscheduled_maintenances', 20, time_2_i)
        @redis.set("name2:PING:#{time_2_i}:unscheduled_maintenance:summary", 'not too bad')
        @redis.zadd('name2:PING:sorted_unscheduled_maintenance_timestamps', time_2_i, time_2_i)

        do_merge

        expect(@redis.zrange('name1:PING:unscheduled_maintenances', 0, -1, :with_scores => true)).to eq(
          [])
        expect(@redis.zrange('name2:PING:unscheduled_maintenances', 0, -1, :with_scores => true)).to eq(
          [[time_2_i.to_s, 20.0], [time_i.to_s, 30.0]])
        expect(@redis.get("name1:PING:#{time_i}:unscheduled_maintenance:summary")).to be_nil
        expect(@redis.get("name2:PING:#{time_i}:unscheduled_maintenance:summary")).to eq('really bad')
        expect(@redis.get("name2:PING:#{time_2_i}:unscheduled_maintenance:summary")).to eq('not too bad')
        expect(@redis.zrange('name1:PING:sorted_unscheduled_maintenance_timestamps', 0, -1, :with_scores => true)).to eq(
          [])
        expect(@redis.zrange('name2:PING:sorted_unscheduled_maintenance_timestamps', 0, -1, :with_scores => true)).to eq(
          [[time_i.to_s, time_i.to_f], [time_2_i.to_s, time_2_i.to_f]])
      end

      it "renames a scheduled maintenance key" do
        @redis.setex('name1:PING:scheduled_maintenance', 30, time_i)

        do_merge

        expect(@redis.get('name1:PING:scheduled_maintenance')).to be_nil
        expect(@redis.get('name2:PING:scheduled_maintenance')).to eq(time_i.to_s)
        expect(@redis.ttl('name2:PING:scheduled_maintenance')).to be <= 30
      end

      it 'merges a scheduled maintenance key (older has longer to live)' do
        @redis.setex('name1:PING:scheduled_maintenance', 60, time_i)
        @redis.setex('name2:PING:scheduled_maintenance', 20, time_2_i)

        do_merge

        expect(@redis.get('name1:PING:scheduled_maintenance')).to be_nil
        expect(@redis.get('name2:PING:scheduled_maintenance')).to eq(time_i.to_s)
        expect(@redis.ttl('name2:PING:scheduled_maintenance')).to be <= 60
      end

      it 'merges a scheduled maintenance key (newer has longer to live)' do
        @redis.setex('name1:PING:scheduled_maintenance', 40, time_i)
        @redis.setex('name2:PING:scheduled_maintenance', 20, time_2_i)

        do_merge

        expect(@redis.get('name1:PING:scheduled_maintenance')).to be_nil
        expect(@redis.get('name2:PING:scheduled_maintenance')).to eq(time_2_i.to_s)
        expect(@redis.ttl('name2:PING:scheduled_maintenance')).to be <= 20
      end

      it 'merges stored scheduled maintenance periods and sorted timestamps' do
        @redis.zadd('name1:PING:scheduled_maintenances', 30, time_i)
        @redis.set("name1:PING:#{time_i}:scheduled_maintenance:summary", 'really bad')
        @redis.zadd('name1:PING:sorted_scheduled_maintenance_timestamps', time_i, time_i)

        @redis.zadd('name2:PING:scheduled_maintenances', 20, time_2_i)
        @redis.set("name2:PING:#{time_2_i}:scheduled_maintenance:summary", 'not too bad')
        @redis.zadd('name2:PING:sorted_scheduled_maintenance_timestamps', time_2_i, time_2_i)

        do_merge

        expect(@redis.zrange('name1:PING:scheduled_maintenances', 0, -1, :with_scores => true)).to eq(
          [])
        expect(@redis.zrange('name2:PING:scheduled_maintenances', 0, -1, :with_scores => true)).to eq(
          [[time_2_i.to_s, 20.0], [time_i.to_s, 30.0]])
        expect(@redis.get("name1:PING:#{time_i}:scheduled_maintenance:summary")).to be_nil
        expect(@redis.get("name2:PING:#{time_i}:scheduled_maintenance:summary")).to eq('really bad')
        expect(@redis.get("name2:PING:#{time_2_i}:scheduled_maintenance:summary")).to eq('not too bad')
        expect(@redis.zrange('name1:PING:sorted_scheduled_maintenance_timestamps', 0, -1, :with_scores => true)).to eq(
          [])
        expect(@redis.zrange('name2:PING:sorted_scheduled_maintenance_timestamps', 0, -1, :with_scores => true)).to eq(
          [[time_i.to_s, time_i.to_f], [time_2_i.to_s, time_2_i.to_f]])
      end

      it 'merges current notifications, using old timestamp if no new one' do
        @redis.set('name1:PING:last_problem_notification',         time_i)
        @redis.set('name1:PING:last_unknown_notification',         time_i - 100)
        @redis.set('name1:PING:last_warning_notification',         time_i - 50)
        @redis.set('name1:PING:last_critical_notification',        time_i)
        @redis.set('name1:PING:last_recovery_notification',        time_i - 200)
        @redis.set('name1:PING:last_acknowledgement_notification', time_i - 250)

        @redis.set('name2:PING:last_problem_notification',         time_i + 800)
        @redis.set('name2:PING:last_critical_notification',        time_i + 800)

        do_merge

        expect(@redis.get('name1:PING:last_problem_notification')).to be_nil
        expect(@redis.get('name1:PING:last_unknown_notification')).to be_nil
        expect(@redis.get('name1:PING:last_warning_notification')).to be_nil
        expect(@redis.get('name1:PING:last_critical_notification')).to be_nil
        expect(@redis.get('name1:PING:last_recovery_notification')).to be_nil
        expect(@redis.get('name1:PING:last_acknowledgement_notification')).to be_nil

        expect(@redis.get('name2:PING:last_problem_notification')).to eq((time_i + 800).to_s)
        expect(@redis.get('name2:PING:last_unknown_notification')).to eq((time_i - 100).to_s)
        expect(@redis.get('name2:PING:last_warning_notification')).to eq((time_i - 50).to_s)
        expect(@redis.get('name2:PING:last_critical_notification')).to eq((time_i + 800).to_s)
        expect(@redis.get('name2:PING:last_recovery_notification')).to eq((time_i - 200).to_s)
        expect(@redis.get('name2:PING:last_acknowledgement_notification')).to eq((time_i - 250).to_s)
      end

      it 'merges stored notifications' do
        add_state1

        @redis.lpush('name1:PING:problem_notifications', time_i)
        @redis.lpush('name1:PING:unknown_notifications', time_i - 100)
        @redis.lpush('name1:PING:warning_notifications', time_i - 50)
        @redis.lpush('name1:PING:critical_notifications', time_i)
        @redis.lpush('name1:PING:recovery_notifications', time_i - 200)
        @redis.lpush('name1:PING:acknowledgement_notifications', time_i - 250)

        @redis.lpush('name2:PING:problem_notifications', time_i + 800)
        @redis.lpush('name2:PING:unknown_notifications', time_i + 800)

        do_merge

        expect(@redis.llen('name1:PING:problem_notifications')).to eq(0)
        expect(@redis.llen('name1:PING:unknown_notifications')).to eq(0)
        expect(@redis.llen('name1:PING:warning_notifications')).to eq(0)
        expect(@redis.llen('name1:PING:critical_notifications')).to eq(0)
        expect(@redis.llen('name1:PING:recovery_notifications')).to eq(0)
        expect(@redis.llen('name1:PING:acknowledgement_notifications')).to eq(0)
        expect(@redis.lindex('name2:PING:problem_notifications', 0)).to eq(time_i.to_s)
        expect(@redis.lindex('name2:PING:problem_notifications', 1)).to eq((time_i + 800).to_s)
        expect(@redis.lindex('name2:PING:unknown_notifications', 0)).to eq((time_i - 100).to_s)
        expect(@redis.lindex('name2:PING:unknown_notifications', 1)).to eq((time_i + 800).to_s)
        expect(@redis.lindex('name2:PING:warning_notifications', 0)).to eq((time_i - 50).to_s)
        expect(@redis.lindex('name2:PING:critical_notifications', 0)).to eq(time_i.to_s)
        expect(@redis.lindex('name2:PING:recovery_notifications', 0)).to eq((time_i - 200).to_s)
        expect(@redis.lindex('name2:PING:acknowledgement_notifications', 0)).to eq((time_i - 250).to_s)
      end

      it 'merges alerting checks (no notification state for new)' do
        add_state1

        @redis.zadd('contact_alerting_checks:362:media:email', time_i, 'name1:PING')

        @redis.lpush('name1:PING:problem_notifications', time_i)
        @redis.lpush('name1:PING:critical_notifications', time_i)

        do_merge

        expect(@redis.zrange('contact_alerting_checks:362:media:email', 0, -1, :with_scores => true)).to eq(
          [['name2:PING', time_i.to_f]])
      end

      it 'merges alerting checks (existing notification state for new)' do
        add_state1

        @redis.zadd('contact_alerting_checks:362:media:email', time_i, 'name1:PING')

        @redis.lpush('name1:PING:problem_notifications', time_i)
        @redis.lpush('name1:PING:critical_notifications', time_i)

        @redis.lpush('name2:PING:problem_notifications', time_i + 100)
        @redis.lpush('name2:PING:critical_notifications', time_i + 100)
        @redis.lpush('name2:PING:recovery_notifications', time_i + 150)

        do_merge

        expect(@redis.zrange('contact_alerting_checks:362:media:email', 0, -1, :with_scores => true)).to eq(
          [])
      end

      it 'merges alert blocks (no notification state for new)' do
        @redis.setex('drop_alerts_for_contact:362:email:name1:PING:critical', 30, 30)

        do_merge

        expect(@redis.get('drop_alerts_for_contact:362:email:name1:PING:critical')).to be_nil
        expect(@redis.get('drop_alerts_for_contact:362:email:name2:PING:critical')).to eq(30.to_s)
        expect(@redis.ttl('drop_alerts_for_contact:362:email:name2:PING:critical')).to be <= 30
      end

      it 'merges alert blocks (older has longer to run)' do
        @redis.setex('drop_alerts_for_contact:362:email:name1:PING:critical', 30, 30)
        @redis.setex('drop_alerts_for_contact:362:email:name2:PING:critical', 10, 10)

        do_merge

        expect(@redis.get('drop_alerts_for_contact:362:email:name1:PING:critical')).to be_nil
        expect(@redis.get('drop_alerts_for_contact:362:email:name2:PING:critical')).to eq(30.to_s)
        expect(@redis.ttl('drop_alerts_for_contact:362:email:name2:PING:critical')).to be <= 30
      end

      it 'merges alert blocks (newer has longer to run)' do
        @redis.setex('drop_alerts_for_contact:362:email:name1:PING:critical', 30, 30)
        @redis.setex('drop_alerts_for_contact:362:email:name2:PING:critical', 60, 60)

        do_merge

        expect(@redis.get('drop_alerts_for_contact:362:email:name1:PING:critical')).to be_nil
        expect(@redis.get('drop_alerts_for_contact:362:email:name2:PING:critical')).to eq(60.to_s)
        expect(@redis.ttl('drop_alerts_for_contact:362:email:name2:PING:critical')).to be <= 60
      end

    end

  end

end
