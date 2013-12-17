require 'spec_helper'

require 'flapjack/data/entity'
require 'flapjack/data/entity_check'
require 'flapjack/data/tag_set'

describe Flapjack::Data::EntityCheck, :redis => true do

  let(:name)  { 'abc-123' }
  let(:check) { 'ping' }

  let(:half_an_hour) { 30 * 60 }

  before(:each) do
    Flapjack::Data::Contact.add({'id'         => '362',
                                 'first_name' => 'John',
                                 'last_name'  => 'Johnson',
                                 'email'      => 'johnj@example.com' })

    Flapjack::Data::Entity.add({'id'   => '5000',
                                'name' => name,
                                'contacts' => ['362']})
  end

  it "is created for an event id" do
    ec = Flapjack::Data::EntityCheck.for_event_id("#{name}:ping")
    expect(ec).not_to be_nil
    expect(ec.entity).not_to be_nil
    expect(ec.entity.name).not_to be_nil
    expect(ec.entity.name).to eq(name)
    expect(ec.check).not_to be_nil
    expect(ec.check).to eq('ping')
  end

  it "is created for an entity name" do
    ec = Flapjack::Data::EntityCheck.for_entity_name(name, 'ping')
    expect(ec).not_to be_nil
    expect(ec.entity).not_to be_nil
    expect(ec.entity.name).not_to be_nil
    expect(ec.entity.name).to eq(name)
    expect(ec.check).not_to be_nil
    expect(ec.check).to eq('ping')
  end

  it "is created for an entity id" do
    ec = Flapjack::Data::EntityCheck.for_entity_id(5000, 'ping')
    expect(ec).not_to be_nil
    expect(ec.entity).not_to be_nil
    expect(ec.entity.name).not_to be_nil
    expect(ec.entity.name).to eq(name)
    expect(ec.check).not_to be_nil
    expect(ec.check).to eq('ping')
  end

  it "is created for an entity object" do
    e = Flapjack::Data::Entity.find_by_name(name)
    ec = Flapjack::Data::EntityCheck.for_entity(e, 'ping')
    expect(ec).not_to be_nil
    expect(ec.entity).not_to be_nil
    expect(ec.entity.name).not_to be_nil
    expect(ec.entity.name).to eq(name)
    expect(ec.check).not_to be_nil
    expect(ec.check).to eq('ping')
  end

  it "is not created for a missing entity" do
    expect {
      Flapjack::Data::EntityCheck.for_entity(nil, 'ping')
    }.to raise_error
  end

  it "finds all checks"

  it "returns a count of all checks"

  it "finds all checks grouped by entity"

  it "finds all checks for an entity name"


  it "finds all failing checks"

  it "returns a count of all failing checks"

  it "finds all failing checks grouped by entity"


  it "finds all unacknowledged failing checks"

  it "returns its entity's name" do
    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
    expect(ec.entity_name).to eq(name)
  end

  context "maintenance" do

    it "returns that it is in unscheduled maintenance" do
      Flapjack.redis.set("#{name}:#{check}:unscheduled_maintenance", Time.now.to_i.to_s)

      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
      expect(ec).to be_in_unscheduled_maintenance
    end

    it "returns that it is not in unscheduled maintenance" do
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
      expect(ec).not_to be_in_unscheduled_maintenance
    end

    it "returns that it is in scheduled maintenance" do
      Flapjack.redis.set("#{name}:#{check}:scheduled_maintenance", Time.now.to_i.to_s)

      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
      expect(ec).to be_in_scheduled_maintenance
    end

    it "returns that it is not in scheduled maintenance" do
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
      expect(ec).not_to be_in_scheduled_maintenance
    end

    it "returns its current maintenance period" do
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
      expect(ec.current_maintenance(:scheduled => true)).to be_nil

      t = Time.now.to_i

      ec.create_unscheduled_maintenance(t, half_an_hour, :summary => 'oops')
      expect(ec.current_maintenance).to eq({:start_time => t,
                                        :duration => half_an_hour,
                                        :summary => 'oops'})
    end

    it "creates an unscheduled maintenance period" do
      t = Time.now.to_i
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
      ec.create_unscheduled_maintenance(t, half_an_hour, :summary => 'oops')

      expect(ec).to be_in_unscheduled_maintenance

      umps = ec.maintenances(nil, nil, :scheduled => false)
      expect(umps).not_to be_nil
      expect(umps).to be_an(Array)
      expect(umps.size).to eq(1)
      expect(umps[0]).to be_a(Hash)

      start_time = umps[0][:start_time]
      expect(start_time).not_to be_nil
      expect(start_time).to be_an(Integer)
      expect(start_time).to eq(t)

      duration = umps[0][:duration]
      expect(duration).not_to be_nil
      expect(duration).to be_a(Float)
      expect(duration).to eq(half_an_hour)

      summary = Flapjack.redis.get("#{name}:#{check}:#{t}:unscheduled_maintenance:summary")
      expect(summary).not_to be_nil
      expect(summary).to eq('oops')
    end

    it "creates an unscheduled maintenance period and ends the current one early", :time => true do
      t = Time.now.to_i
      later_t = t + (15 * 60)
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
      ec.create_unscheduled_maintenance(t, half_an_hour, :summary => 'oops')
      Delorean.time_travel_to( Time.at(later_t) )
      ec.create_unscheduled_maintenance(later_t, half_an_hour, :summary => 'spoo')

      expect(ec).to be_in_unscheduled_maintenance

      umps = ec.maintenances(nil, nil, :scheduled => false)
      expect(umps).not_to be_nil
      expect(umps).to be_an(Array)
      expect(umps.size).to eq(2)
      expect(umps[0]).to be_a(Hash)

      start_time = umps[0][:start_time]
      expect(start_time).not_to be_nil
      expect(start_time).to be_an(Integer)
      expect(start_time).to eq(t)

      duration = umps[0][:duration]
      expect(duration).not_to be_nil
      expect(duration).to be_a(Float)
      expect(duration).to eq(15 * 60)

      start_time_curr = umps[1][:start_time]
      expect(start_time_curr).not_to be_nil
      expect(start_time_curr).to be_an(Integer)
      expect(start_time_curr).to eq(later_t)

      duration_curr = umps[1][:duration]
      expect(duration_curr).not_to be_nil
      expect(duration_curr).to be_a(Float)
      expect(duration_curr).to eq(half_an_hour)
    end

    it "ends an unscheduled maintenance period" do
      t = Time.now.to_i
      later_t = t + (15 * 60)
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)

      ec.create_unscheduled_maintenance(t, half_an_hour, :summary => 'oops')
      expect(ec).to be_in_unscheduled_maintenance

      Delorean.time_travel_to( Time.at(later_t) )
      expect(ec).to be_in_unscheduled_maintenance
      ec.end_unscheduled_maintenance(later_t)
      expect(ec).not_to be_in_unscheduled_maintenance

      umps = ec.maintenances(nil, nil, :scheduled => false)
      expect(umps).not_to be_nil
      expect(umps).to be_an(Array)
      expect(umps.size).to eq(1)
      expect(umps[0]).to be_a(Hash)

      start_time = umps[0][:start_time]
      expect(start_time).not_to be_nil
      expect(start_time).to be_an(Integer)
      expect(start_time).to eq(t)

      duration = umps[0][:duration]
      expect(duration).not_to be_nil
      expect(duration).to be_a(Float)
      expect(duration).to eq(15 * 60)
    end

    it "creates a scheduled maintenance period for a future time" do
      t = Time.now.to_i
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
      ec.create_scheduled_maintenance(t + (60 * 60),
        half_an_hour, :summary => "30 minutes")

      smps = ec.maintenances(nil, nil, :scheduled => true)
      expect(smps).not_to be_nil
      expect(smps).to be_an(Array)
      expect(smps.size).to eq(1)
      expect(smps[0]).to be_a(Hash)

      start_time = smps[0][:start_time]
      expect(start_time).not_to be_nil
      expect(start_time).to be_an(Integer)
      expect(start_time).to eq(t + (60 * 60))

      duration = smps[0][:duration]
      expect(duration).not_to be_nil
      expect(duration).to be_a(Float)
      expect(duration).to eq(half_an_hour)
    end

    # TODO this should probably enforce that it starts in the future
    it "creates a scheduled maintenance period covering the current time" do
      t = Time.now.to_i
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
      ec.create_scheduled_maintenance(t - (60 * 60),
        2 * (60 * 60), :summary => "2 hours")

      smps = ec.maintenances(nil, nil, :scheduled => true)
      expect(smps).not_to be_nil
      expect(smps).to be_an(Array)
      expect(smps.size).to eq(1)
      expect(smps[0]).to be_a(Hash)

      start_time = smps[0][:start_time]
      expect(start_time).not_to be_nil
      expect(start_time).to be_an(Integer)
      expect(start_time).to eq(t - (60 * 60))

      duration = smps[0][:duration]
      expect(duration).not_to be_nil
      expect(duration).to be_a(Float)
      expect(duration).to eq(2 * (60 * 60))
    end

    it "removes a scheduled maintenance period for a future time" do
      t = Time.now.to_i
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
      ec.create_scheduled_maintenance(t + (60 * 60),
        2 * (60 * 60), :summary => "2 hours")

      ec.end_scheduled_maintenance(t + (60 * 60))

      smps = ec.maintenances(nil, nil, :scheduled => true)
      expect(smps).not_to be_nil
      expect(smps).to be_an(Array)
      expect(smps).to be_empty
    end

    # maint period starts an hour from now, goes for two hours -- at 30 minutes into
    # it we stop it, and its duration should be 30 minutes
    it "shortens a scheduled maintenance period covering a current time", :time => true do
      t = Time.now.to_i
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
      ec.create_scheduled_maintenance(t + (60 * 60),
        2 * (60 * 60), :summary => "2 hours")

      Delorean.time_travel_to( Time.at(t + (90 * 60)) )

      ec.end_scheduled_maintenance(t + (60 * 60))

      smps = ec.maintenances(nil, nil, :scheduled => true)
      expect(smps).not_to be_nil
      expect(smps).to be_an(Array)
      expect(smps).not_to be_empty
      expect(smps.size).to eq(1)
      expect(smps.first[:duration]).to eq(30 * 60)
    end

    it "does not alter or remove a scheduled maintenance period covering a past time", :time => true do
      t = Time.now.to_i
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
      ec.create_scheduled_maintenance(t + (60 * 60),
        2 * (60 * 60), :summary => "2 hours")

      Delorean.time_travel_to( Time.at(t + (6 * (60 * 60)) ))

      ec.end_scheduled_maintenance(t + (60 * 60))

      smps = ec.maintenances(nil, nil, :scheduled => true)
      expect(smps).not_to be_nil
      expect(smps).to be_an(Array)
      expect(smps).not_to be_empty
      expect(smps.size).to eq(1)
      expect(smps.first[:duration]).to eq(2 * (60 * 60))
    end

    it "returns a list of scheduled maintenance periods" do
      t = Time.now.to_i
      five_hours_ago = t - (60 * 60 * 5)
      three_hours_ago = t - (60 * 60 * 3)

      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
      ec.create_scheduled_maintenance(five_hours_ago, half_an_hour,
        :summary => "first")
      ec.create_scheduled_maintenance(three_hours_ago, half_an_hour,
        :summary => "second")

      smp = ec.maintenances(nil, nil, :scheduled => true)
      expect(smp).not_to be_nil
      expect(smp).to be_an(Array)
      expect(smp.size).to eq(2)
      expect(smp[0]).to eq({:start_time => five_hours_ago,
                        :end_time   => five_hours_ago + half_an_hour,
                        :duration   => half_an_hour,
                        :summary    => "first"})
      expect(smp[1]).to eq({:start_time => three_hours_ago,
                        :end_time   => three_hours_ago + half_an_hour,
                        :duration   => half_an_hour,
                        :summary    => "second"})
    end

    it "returns a list of unscheduled maintenance periods" do
      t = Time.now.to_i
      five_hours_ago = t - (60 * 60 * 5)
      three_hours_ago = t - (60 * 60 * 3)

      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
      ec.create_unscheduled_maintenance(five_hours_ago,
        half_an_hour, :summary => "first")
      ec.create_unscheduled_maintenance(three_hours_ago,
        half_an_hour, :summary => "second")

      ump =  ec.maintenances(nil, nil, :scheduled => false)
      expect(ump).not_to be_nil
      expect(ump).to be_an(Array)
      expect(ump.size).to eq(2)
      expect(ump[0]).to eq({:start_time => five_hours_ago,
                        :end_time   => five_hours_ago + half_an_hour,
                        :duration   => half_an_hour,
                        :summary    => "first"})
      expect(ump[1]).to eq({:start_time => three_hours_ago,
                        :end_time   => three_hours_ago + half_an_hour,
                        :duration   => half_an_hour,
                        :summary    => "second"})
    end

  end

  it "returns its state" do
    Flapjack.redis.hset("check:#{name}:#{check}", 'state', 'ok')

    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
    state = ec.state
    expect(state).not_to be_nil
    expect(state).to eq('ok')
  end

  it "updates state" do
    Flapjack.redis.hset("check:#{name}:#{check}", 'state', 'ok')

    old_timestamp = Flapjack.redis.hget("check:#{name}:#{check}", 'last_update')
    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
    ec.update_state('critical')

    state = Flapjack.redis.hget("check:#{name}:#{check}", 'state')
    expect(state).not_to be_nil
    expect(state).to eq('critical')

    new_timestamp = Flapjack.redis.hget("check:#{name}:#{check}", 'last_update')
    expect(new_timestamp).not_to eq(old_timestamp)
  end

  it "updates enabled checks" do
    ts = Time.now.to_i
    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
    ec.last_update = ts

    saved_check_ts = Flapjack.redis.zscore("current_checks:#{name}", check)
    expect(saved_check_ts).not_to be_nil
    expect(saved_check_ts).to eq(ts)
    saved_entity_ts = Flapjack.redis.zscore("current_entities", name)
    expect(saved_entity_ts).not_to be_nil
    expect(saved_entity_ts).to eq(ts)
  end

  it "exposes that it is enabled" do
    Flapjack.redis.zadd("current_checks:#{name}", Time.now.to_i, check)
    Flapjack.redis.zadd("current_entities", Time.now.to_i, name)
    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)

    e = ec.enabled?
    expect(e).to be_truthy
  end

  it "exposes that it is disabled" do
    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)

    e = ec.enabled?
    expect(e).to be_falsey
  end

  it "disables checks" do
    Flapjack.redis.zadd("current_checks:#{name}", Time.now.to_i, check)
    Flapjack.redis.zadd("current_entities", Time.now.to_i, name)
    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
    ec.disable!

    saved_check_ts = Flapjack.redis.zscore("current_checks:#{name}", check)
    saved_entity_ts = Flapjack.redis.zscore("current_entities", name)
    expect(saved_check_ts).to be_nil
    expect(saved_entity_ts).to be_nil
  end

  it "does not update state with invalid value" do
    Flapjack.redis.hset("check:#{name}:#{check}", 'state', 'ok')

    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
    ec.update_state('silly')

    state = Flapjack.redis.hget("check:#{name}:#{check}", 'state')
    expect(state).not_to be_nil
    expect(state).to eq('ok')
  end

  it "does not update state with a repeated state value" do
    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
    ec.update_state('critical', :summary => 'small problem')
    changed_at = Flapjack.redis.hget("check:#{name}:#{check}", 'last_change')
    summary = Flapjack.redis.hget("check:#{name}:#{check}", 'summary')

    ec.update_state('critical', :summary => 'big problem')
    new_changed_at = Flapjack.redis.hget("check:#{name}:#{check}", 'last_change')
    new_summary = Flapjack.redis.hget("check:#{name}:#{check}", 'summary')

    expect(changed_at).not_to be_nil
    expect(new_changed_at).not_to be_nil
    expect(new_changed_at).to eq(changed_at)

    expect(summary).not_to be_nil
    expect(new_summary).not_to be_nil
    expect(new_summary).not_to eq(summary)
    expect(summary).to eq('small problem')
    expect(new_summary).to eq('big problem')
  end

  def time_before(t, min, sec = 0)
    t - ((60 * min) + sec)
  end

  it "returns a list of historical states for a time range" do
    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)

    t = Time.now.to_i
    ec.update_state('ok', :timestamp => time_before(t, 5), :summary => 'a')
    ec.update_state('critical', :timestamp => time_before(t, 4), :summary => 'b')
    ec.update_state('ok', :timestamp => time_before(t, 3), :summary => 'c')
    ec.update_state('critical', :timestamp => time_before(t, 2), :summary => 'd')
    ec.update_state('ok', :timestamp => time_before(t, 1), :summary => 'e')

    states = ec.historical_states(time_before(t, 4), t)
    expect(states).not_to be_nil
    expect(states).to be_an(Array)
    expect(states.size).to eq(4)
    expect(states[0][:summary]).to eq('b')
    expect(states[1][:summary]).to eq('c')
    expect(states[2][:summary]).to eq('d')
    expect(states[3][:summary]).to eq('e')
  end

  it "returns a list of historical unscheduled maintenances for a time range" do
    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)

    t = Time.now.to_i
    ec.update_state('ok', :timestamp => time_before(t, 5), :summary => 'a')
    ec.update_state('critical', :timestamp => time_before(t, 4), :summary => 'b')
    ec.update_state('ok', :timestamp => time_before(t, 3), :summary => 'c')
    ec.update_state('critical', :timestamp => time_before(t, 2), :summary => 'd')
    ec.update_state('ok', :timestamp => time_before(t, 1), :summary => 'e')

    states = ec.historical_states(time_before(t, 4), t)
    expect(states).not_to be_nil
    expect(states).to be_an(Array)
    expect(states.size).to eq(4)
    expect(states[0][:summary]).to eq('b')
    expect(states[1][:summary]).to eq('c')
    expect(states[2][:summary]).to eq('d')
    expect(states[3][:summary]).to eq('e')
  end

  it "returns a list of historical scheduled maintenances for a time range" do
    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)

    t = Time.now.to_i

    ec.create_scheduled_maintenance(time_before(t, 180),
      half_an_hour, :summary => "a")
    ec.create_scheduled_maintenance(time_before(t, 120),
      half_an_hour, :summary => "b")
    ec.create_scheduled_maintenance(time_before(t, 60),
      half_an_hour, :summary => "c")

    sched_maint_periods = ec.maintenances(time_before(t, 150), t,
      :scheduled => true)
    expect(sched_maint_periods).not_to be_nil
    expect(sched_maint_periods).to be_an(Array)
    expect(sched_maint_periods.size).to eq(2)
    expect(sched_maint_periods[0][:summary]).to eq('b')
    expect(sched_maint_periods[1][:summary]).to eq('c')
  end

  it "returns that it has failed" do
    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)

    Flapjack.redis.hset("check:#{name}:#{check}", 'state', 'warning')
    expect(ec).to be_failed

    Flapjack.redis.hset("check:#{name}:#{check}", 'state', 'critical')
    expect(ec).to be_failed

    Flapjack.redis.hset("check:#{name}:#{check}", 'state', 'unknown')
    expect(ec).to be_failed
  end

  it "returns that it has not failed" do
    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)

    Flapjack.redis.hset("check:#{name}:#{check}", 'state', 'ok')
    expect(ec).not_to be_failed

    Flapjack.redis.hset("check:#{name}:#{check}", 'state', 'acknowledgement')
    expect(ec).not_to be_failed
  end

  it "returns a status summary" do
    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)

    t = Time.now.to_i
    ec.update_state('ok', :timestamp => time_before(t, 5), :summary => 'a')
    ec.update_state('critical', :timestamp => time_before(t, 4), :summary => 'b')
    ec.update_state('ok', :timestamp => time_before(t, 3), :summary => 'c')
    ec.update_state('critical', :timestamp => time_before(t, 2), :summary => 'd')

    summary = ec.summary
    expect(summary).to eq('d')
  end

  it "returns timestamps for its last notifications" do
    t = Time.now.to_i
    Flapjack.redis.set("#{name}:#{check}:last_problem_notification", t - 30)
    Flapjack.redis.set("#{name}:#{check}:last_acknowledgement_notification", t - 15)
    Flapjack.redis.set("#{name}:#{check}:last_recovery_notification", t)

    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
    expect(ec.last_notification_for_state(:problem)[:timestamp]).to eq(t - 30)
    expect(ec.last_notification_for_state(:acknowledgement)[:timestamp]).to eq(t - 15)
    expect(ec.last_notification_for_state(:recovery)[:timestamp]).to eq(t)
  end

  it "finds all related contacts" do
    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
    contacts = ec.contacts
    expect(contacts).not_to be_nil
    expect(contacts).to be_an(Array)
    expect(contacts.size).to eq(1)
    expect(contacts.first.name).to eq('John Johnson')
  end

  it "generates ephemeral tags for itself" do
    ec = Flapjack::Data::EntityCheck.for_entity_name('foo-app-01.example.com', 'Disk / Utilisation')
    tags = ec.tags
    expect(tags).not_to be_nil
    expect(tags).to be_a(Flapjack::Data::TagSet)
    expect(['foo-app-01', 'example.com', 'disk', '/', 'utilisation'].to_set.subset?(tags)).to be_truthy
  end

end
