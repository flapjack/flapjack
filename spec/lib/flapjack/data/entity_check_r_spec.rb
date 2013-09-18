require 'spec_helper'

require 'flapjack/data/entity_check_r'
require 'flapjack/data/entity_r'

describe Flapjack::Data::EntityCheckR, :redis => true do

  let(:half_an_hour) { 30 * 60 }

  # def create_contact
  #   redis.hmset('flapjack/data/contact_r:1:attrs', {'first_name' => 'John',
  #     'last_name' => 'Smith', 'email' => 'jsmith@example.com'}.flatten)
  #   redis.sadd('flapjack/data/contact_r::ids', '1')
  # end

  let(:entity_name) { 'foo.example.com' }
  let(:check_name)  { 'PING' }

  let(:redis) { Flapjack.redis }

  def create_entity(ent_name, id)
    redis.multi
    redis.hmset("flapjack/data/entity_r:#{id}:attrs", {'name' => ent_name}.flatten)
    redis.sadd('flapjack/data/entity_r::ids', id.to_s)
    redis.sadd("flapjack/data/entity_r::by_name:#{ent_name}", id.to_s)
    redis.exec
  end

  def create_check(ent_name, chk_name, id)
    raise "entity not found" unless entity = Flapjack::Data::EntityR.find_by(:name, ent_name).first
    redis.multi
    redis.hmset("flapjack/data/entity_check_r:#{id}:attrs", {'name' => chk_name,
      'entity_name' => entity.name, 'state' => 'ok', 'enabled' => 'true'}.flatten)
    redis.sadd('flapjack/data/entity_check_r::ids', id.to_s)
    redis.sadd("flapjack/data/entity_check_r::by_name:#{chk_name}", id.to_s)
    redis.sadd("flapjack/data/entity_check_r::by_entity_name:#{entity.name}", id.to_s)
    redis.sadd('flapjack/data/entity_check_r::by_state:ok', id.to_s)
    redis.sadd('flapjack/data/entity_check_r::by_enabled:true', id.to_s)

    redis.sadd("flapjack/data/entity_r:#{entity.id}:check_ids", id.to_s)
    redis.exec
  end

  context "class-level finders" do

    before(:each) do
      create_entity(entity_name, 1)
      create_check(entity_name, check_name, 1)
    end

    it "is found for an event id" do
      ec = Flapjack::Data::EntityCheckR.find_for_event_id("#{entity_name}:#{check_name}")
      ec.should_not be_nil
      ec.entity.should_not be_nil
      ec.entity.name.should_not be_nil
      ec.entity.name.should == entity_name
      ec.name.should_not be_nil
      ec.name.should == check_name
    end

    it "is found for an entity name" do
      ec = Flapjack::Data::EntityCheckR.find_for_entity_name(entity_name, check_name)
      ec.should_not be_nil
      ec.entity.should_not be_nil
      ec.entity.name.should_not be_nil
      ec.entity.name.should == entity_name
      ec.name.should_not be_nil
      ec.name.should == check_name
    end

    it "is found for an entity id" do
      ec = Flapjack::Data::EntityCheckR.find_for_entity_id('1', check_name)
      ec.should_not be_nil
      ec.entity.should_not be_nil
      ec.entity.name.should_not be_nil
      ec.entity.name.should == entity_name
      ec.name.should_not be_nil
      ec.name.should == check_name
    end

    it "is found for an entity object" do
      ec = Flapjack::Data::EntityCheckR.find_for_entity(Flapjack::Data::EntityR.find_by_id('1'), check_name)
      ec.should_not be_nil
      ec.entity.should_not be_nil
      ec.entity.name.should_not be_nil
      ec.entity.name.should == entity_name
      ec.name.should_not be_nil
      ec.name.should == check_name
    end

  end

  it "is not created for a missing entity" do
    expect {
      Flapjack::Data::EntityCheck.for_entity(nil, 'ping')
    }.to raise_error
  end

  it "finds all checks" do
    create_entity(entity_name, 1)
    create_entity("another", 2)
    create_check(entity_name, check_name, 1)
    create_check(entity_name, "SSH", 2)
    create_check("another", "HTTP", 3)

    checks = Flapjack::Data::EntityCheckR.all
    checks.should_not be_nil
    checks.should be_an(Array)
    checks.should have(3).checks
  end

  it "returns a count of all checks"

  it "finds all checks grouped by entity"

  it "finds all checks for an entity name"


  it "finds all failing checks"

  it "returns a count of all failing checks"

  it "finds all failing checks grouped by entity"

  it "finds all unacknowledged failing checks"

  it "returns its entity's name" do
    create_entity(entity_name, 1)
    create_check(entity_name, check_name, 1)

    ec = Flapjack::Data::EntityCheckR.find_for_entity_name(entity_name, check_name)
    ec.should_not be_nil
    ec.entity_name.should == entity_name
  end

  # context "maintenance" do

  #   it "returns that it is in unscheduled maintenance" do
  #     Flapjack.redis.set("#{name}:#{check}:unscheduled_maintenance", Time.now.to_i.to_s)

  #     ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
  #     ec.should be_in_unscheduled_maintenance
  #   end

  #   it "returns that it is not in unscheduled maintenance" do
  #     ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
  #     ec.should_not be_in_unscheduled_maintenance
  #   end

  #   it "returns that it is in scheduled maintenance" do
  #     Flapjack.redis.set("#{name}:#{check}:scheduled_maintenance", Time.now.to_i.to_s)

  #     ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
  #     ec.should be_in_scheduled_maintenance
  #   end

  #   it "returns that it is not in scheduled maintenance" do
  #     ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
  #     ec.should_not be_in_scheduled_maintenance
  #   end

  #   it "returns its current maintenance period" do
  #     ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
  #     ec.current_maintenance(:scheduled => true).should be_nil

  #     t = Time.now.to_i

  #     ec.create_unscheduled_maintenance(t, half_an_hour, :summary => 'oops')
  #     ec.current_maintenance.should == {:start_time => t,
  #                                       :duration => half_an_hour,
  #                                       :summary => 'oops'}
  #   end

  #   it "creates an unscheduled maintenance period" do
  #     t = Time.now.to_i
  #     ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
  #     ec.create_unscheduled_maintenance(t, half_an_hour, :summary => 'oops')

  #     ec.should be_in_unscheduled_maintenance

  #     umps = ec.maintenances(nil, nil, :scheduled => false)
  #     umps.should_not be_nil
  #     umps.should be_an(Array)
  #     umps.should have(1).unscheduled_maintenance_period
  #     umps[0].should be_a(Hash)

  #     start_time = umps[0][:start_time]
  #     start_time.should_not be_nil
  #     start_time.should be_an(Integer)
  #     start_time.should == t

  #     duration = umps[0][:duration]
  #     duration.should_not be_nil
  #     duration.should be_a(Float)
  #     duration.should == half_an_hour

  #     summary = Flapjack.redis.get("#{name}:#{check}:#{t}:unscheduled_maintenance:summary")
  #     summary.should_not be_nil
  #     summary.should == 'oops'
  #   end

  #   it "creates an unscheduled maintenance period and ends the current one early", :time => true do
  #     t = Time.now.to_i
  #     later_t = t + (15 * 60)
  #     ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
  #     ec.create_unscheduled_maintenance(t, half_an_hour, :summary => 'oops')
  #     Delorean.time_travel_to( Time.at(later_t) )
  #     ec.create_unscheduled_maintenance(later_t, half_an_hour, :summary => 'spoo')

  #     ec.should be_in_unscheduled_maintenance

  #     umps = ec.maintenances(nil, nil, :scheduled => false)
  #     umps.should_not be_nil
  #     umps.should be_an(Array)
  #     umps.should have(2).unscheduled_maintenance_periods
  #     umps[0].should be_a(Hash)

  #     start_time = umps[0][:start_time]
  #     start_time.should_not be_nil
  #     start_time.should be_an(Integer)
  #     start_time.should == t

  #     duration = umps[0][:duration]
  #     duration.should_not be_nil
  #     duration.should be_a(Float)
  #     duration.should == (15 * 60)

  #     start_time_curr = umps[1][:start_time]
  #     start_time_curr.should_not be_nil
  #     start_time_curr.should be_an(Integer)
  #     start_time_curr.should == later_t

  #     duration_curr = umps[1][:duration]
  #     duration_curr.should_not be_nil
  #     duration_curr.should be_a(Float)
  #     duration_curr.should == half_an_hour
  #   end

  #   it "ends an unscheduled maintenance period" do
  #     t = Time.now.to_i
  #     later_t = t + (15 * 60)
  #     ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)

  #     ec.create_unscheduled_maintenance(t, half_an_hour, :summary => 'oops')
  #     ec.should be_in_unscheduled_maintenance

  #     Delorean.time_travel_to( Time.at(later_t) )
  #     ec.should be_in_unscheduled_maintenance
  #     ec.end_unscheduled_maintenance(later_t)
  #     ec.should_not be_in_unscheduled_maintenance

  #     umps = ec.maintenances(nil, nil, :scheduled => false)
  #     umps.should_not be_nil
  #     umps.should be_an(Array)
  #     umps.should have(1).unscheduled_maintenance_period
  #     umps[0].should be_a(Hash)

  #     start_time = umps[0][:start_time]
  #     start_time.should_not be_nil
  #     start_time.should be_an(Integer)
  #     start_time.should == t

  #     duration = umps[0][:duration]
  #     duration.should_not be_nil
  #     duration.should be_a(Float)
  #     duration.should == (15 * 60)
  #   end

  #   it "creates a scheduled maintenance period for a future time" do
  #     t = Time.now.to_i
  #     ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
  #     ec.create_scheduled_maintenance(t + (60 * 60),
  #       half_an_hour, :summary => "30 minutes")

  #     smps = ec.maintenances(nil, nil, :scheduled => true)
  #     smps.should_not be_nil
  #     smps.should be_an(Array)
  #     smps.should have(1).scheduled_maintenance_period
  #     smps[0].should be_a(Hash)

  #     start_time = smps[0][:start_time]
  #     start_time.should_not be_nil
  #     start_time.should be_an(Integer)
  #     start_time.should == (t + (60 * 60))

  #     duration = smps[0][:duration]
  #     duration.should_not be_nil
  #     duration.should be_a(Float)
  #     duration.should == half_an_hour
  #   end

  #   # TODO this should probably enforce that it starts in the future
  #   it "creates a scheduled maintenance period covering the current time" do
  #     t = Time.now.to_i
  #     ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
  #     ec.create_scheduled_maintenance(t - (60 * 60),
  #       2 * (60 * 60), :summary => "2 hours")

  #     smps = ec.maintenances(nil, nil, :scheduled => true)
  #     smps.should_not be_nil
  #     smps.should be_an(Array)
  #     smps.should have(1).scheduled_maintenance_period
  #     smps[0].should be_a(Hash)

  #     start_time = smps[0][:start_time]
  #     start_time.should_not be_nil
  #     start_time.should be_an(Integer)
  #     start_time.should == (t - (60 * 60))

  #     duration = smps[0][:duration]
  #     duration.should_not be_nil
  #     duration.should be_a(Float)
  #     duration.should == 2 * (60 * 60)
  #   end

  #   it "removes a scheduled maintenance period for a future time" do
  #     t = Time.now.to_i
  #     ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
  #     ec.create_scheduled_maintenance(t + (60 * 60),
  #       2 * (60 * 60), :summary => "2 hours")

  #     ec.end_scheduled_maintenance(t + (60 * 60))

  #     smps = ec.maintenances(nil, nil, :scheduled => true)
  #     smps.should_not be_nil
  #     smps.should be_an(Array)
  #     smps.should be_empty
  #   end

  #   # maint period starts an hour from now, goes for two hours -- at 30 minutes into
  #   # it we stop it, and its duration should be 30 minutes
  #   it "shortens a scheduled maintenance period covering a current time", :time => true do
  #     t = Time.now.to_i
  #     ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
  #     ec.create_scheduled_maintenance(t + (60 * 60),
  #       2 * (60 * 60), :summary => "2 hours")

  #     Delorean.time_travel_to( Time.at(t + (90 * 60)) )

  #     ec.end_scheduled_maintenance(t + (60 * 60))

  #     smps = ec.maintenances(nil, nil, :scheduled => true)
  #     smps.should_not be_nil
  #     smps.should be_an(Array)
  #     smps.should_not be_empty
  #     smps.should have(1).item
  #     smps.first[:duration].should == (30 * 60)
  #   end

  #   it "does not alter or remove a scheduled maintenance period covering a past time", :time => true do
  #     t = Time.now.to_i
  #     ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
  #     ec.create_scheduled_maintenance(t + (60 * 60),
  #       2 * (60 * 60), :summary => "2 hours")

  #     Delorean.time_travel_to( Time.at(t + (6 * (60 * 60)) ))

  #     ec.end_scheduled_maintenance(t + (60 * 60))

  #     smps = ec.maintenances(nil, nil, :scheduled => true)
  #     smps.should_not be_nil
  #     smps.should be_an(Array)
  #     smps.should_not be_empty
  #     smps.should have(1).item
  #     smps.first[:duration].should == 2 * (60 * 60)
  #   end

  #   it "returns a list of scheduled maintenance periods" do
  #     t = Time.now.to_i
  #     five_hours_ago = t - (60 * 60 * 5)
  #     three_hours_ago = t - (60 * 60 * 3)

  #     ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
  #     ec.create_scheduled_maintenance(five_hours_ago, half_an_hour,
  #       :summary => "first")
  #     ec.create_scheduled_maintenance(three_hours_ago, half_an_hour,
  #       :summary => "second")

  #     smp = ec.maintenances(nil, nil, :scheduled => true)
  #     smp.should_not be_nil
  #     smp.should be_an(Array)
  #     smp.should have(2).scheduled_maintenance_periods
  #     smp[0].should == {:start_time => five_hours_ago,
  #                       :end_time   => five_hours_ago + half_an_hour,
  #                       :duration   => half_an_hour,
  #                       :summary    => "first"}
  #     smp[1].should == {:start_time => three_hours_ago,
  #                       :end_time   => three_hours_ago + half_an_hour,
  #                       :duration   => half_an_hour,
  #                       :summary    => "second"}
  #   end

  #   it "returns a list of unscheduled maintenance periods" do
  #     t = Time.now.to_i
  #     five_hours_ago = t - (60 * 60 * 5)
  #     three_hours_ago = t - (60 * 60 * 3)

  #     ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
  #     ec.create_unscheduled_maintenance(five_hours_ago,
  #       half_an_hour, :summary => "first")
  #     ec.create_unscheduled_maintenance(three_hours_ago,
  #       half_an_hour, :summary => "second")

  #     ump =  ec.maintenances(nil, nil, :scheduled => false)
  #     ump.should_not be_nil
  #     ump.should be_an(Array)
  #     ump.should have(2).unscheduled_maintenance_periods
  #     ump[0].should == {:start_time => five_hours_ago,
  #                       :end_time   => five_hours_ago + half_an_hour,
  #                       :duration   => half_an_hour,
  #                       :summary    => "first"}
  #     ump[1].should == {:start_time => three_hours_ago,
  #                       :end_time   => three_hours_ago + half_an_hour,
  #                       :duration   => half_an_hour,
  #                       :summary    => "second"}
  #   end

  # end

  # it "returns its state" do
  #   Flapjack.redis.hset("check:#{name}:#{check}", 'state', 'ok')

  #   ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
  #   state = ec.state
  #   state.should_not be_nil
  #   state.should == 'ok'
  # end

  # it "updates state" do
  #   Flapjack.redis.hset("check:#{name}:#{check}", 'state', 'ok')

  #   ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
  #   ec.update_state('critical')

  #   state = Flapjack.redis.hget("check:#{name}:#{check}", 'state')
  #   state.should_not be_nil
  #   state.should == 'critical'
  # end

  # it "updates enabled checks" do
  #   ts = Time.now.to_i
  #   ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
  #   ec.last_update = ts

  #   saved_check_ts = Flapjack.redis.zscore("current_checks:#{name}", check)
  #   saved_check_ts.should_not be_nil
  #   saved_check_ts.should == ts
  #   saved_entity_ts = Flapjack.redis.zscore("current_entities", name)
  #   saved_entity_ts.should_not be_nil
  #   saved_entity_ts.should == ts
  # end

  # it "exposes that it is enabled" do
  #   Flapjack.redis.zadd("current_checks:#{name}", Time.now.to_i, check)
  #   Flapjack.redis.zadd("current_entities", Time.now.to_i, name)
  #   ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)

  #   e = ec.enabled?
  #   e.should be_true
  # end

  # it "exposes that it is disabled" do
  #   ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)

  #   e = ec.enabled?
  #   e.should be_false
  # end

  # it "disables checks" do
  #   Flapjack.redis.zadd("current_checks:#{name}", Time.now.to_i, check)
  #   Flapjack.redis.zadd("current_entities", Time.now.to_i, name)
  #   ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
  #   ec.disable!

  #   saved_check_ts = Flapjack.redis.zscore("current_checks:#{name}", check)
  #   saved_entity_ts = Flapjack.redis.zscore("current_entities", name)
  #   saved_check_ts.should be_nil
  #   saved_entity_ts.should be_nil
  # end

  # it "does not update state with invalid value" do
  #   Flapjack.redis.hset("check:#{name}:#{check}", 'state', 'ok')

  #   ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
  #   ec.update_state('silly')

  #   state = Flapjack.redis.hget("check:#{name}:#{check}", 'state')
  #   state.should_not be_nil
  #   state.should == 'ok'
  # end

  # it "does not update state with a repeated state value" do
  #   ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
  #   ec.update_state('critical', :summary => 'small problem')
  #   changed_at = Flapjack.redis.hget("check:#{name}:#{check}", 'last_change')
  #   summary = Flapjack.redis.hget("check:#{name}:#{check}", 'summary')

  #   ec.update_state('critical', :summary => 'big problem')
  #   new_changed_at = Flapjack.redis.hget("check:#{name}:#{check}", 'last_change')
  #   new_summary = Flapjack.redis.hget("check:#{name}:#{check}", 'summary')

  #   changed_at.should_not be_nil
  #   new_changed_at.should_not be_nil
  #   new_changed_at.should == changed_at

  #   summary.should_not be_nil
  #   new_summary.should_not be_nil
  #   new_summary.should_not == summary
  #   summary.should == 'small problem'
  #   new_summary.should == 'big problem'
  # end

  # def time_before(t, min, sec = 0)
  #   t - ((60 * min) + sec)
  # end

  # it "returns a list of historical states for a time range" do
  #   ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)

  #   t = Time.now.to_i
  #   ec.update_state('ok', :timestamp => time_before(t, 5), :summary => 'a')
  #   ec.update_state('critical', :timestamp => time_before(t, 4), :summary => 'b')
  #   ec.update_state('ok', :timestamp => time_before(t, 3), :summary => 'c')
  #   ec.update_state('critical', :timestamp => time_before(t, 2), :summary => 'd')
  #   ec.update_state('ok', :timestamp => time_before(t, 1), :summary => 'e')

  #   states = ec.historical_states(time_before(t, 4), t)
  #   states.should_not be_nil
  #   states.should be_an(Array)
  #   states.should have(4).data_hashes
  #   states[0][:summary].should == 'b'
  #   states[1][:summary].should == 'c'
  #   states[2][:summary].should == 'd'
  #   states[3][:summary].should == 'e'
  # end

  # it "returns a list of historical unscheduled maintenances for a time range" do
  #   ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)

  #   t = Time.now.to_i
  #   ec.update_state('ok', :timestamp => time_before(t, 5), :summary => 'a')
  #   ec.update_state('critical', :timestamp => time_before(t, 4), :summary => 'b')
  #   ec.update_state('ok', :timestamp => time_before(t, 3), :summary => 'c')
  #   ec.update_state('critical', :timestamp => time_before(t, 2), :summary => 'd')
  #   ec.update_state('ok', :timestamp => time_before(t, 1), :summary => 'e')

  #   states = ec.historical_states(time_before(t, 4), t)
  #   states.should_not be_nil
  #   states.should be_an(Array)
  #   states.should have(4).data_hashes
  #   states[0][:summary].should == 'b'
  #   states[1][:summary].should == 'c'
  #   states[2][:summary].should == 'd'
  #   states[3][:summary].should == 'e'
  # end

  # it "returns a list of historical scheduled maintenances for a time range" do
  #   ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)

  #   t = Time.now.to_i

  #   ec.create_scheduled_maintenance(time_before(t, 180),
  #     half_an_hour, :summary => "a")
  #   ec.create_scheduled_maintenance(time_before(t, 120),
  #     half_an_hour, :summary => "b")
  #   ec.create_scheduled_maintenance(time_before(t, 60),
  #     half_an_hour, :summary => "c")

  #   sched_maint_periods = ec.maintenances(time_before(t, 150), t,
  #     :scheduled => true)
  #   sched_maint_periods.should_not be_nil
  #   sched_maint_periods.should be_an(Array)
  #   sched_maint_periods.should have(2).data_hashes
  #   sched_maint_periods[0][:summary].should == 'b'
  #   sched_maint_periods[1][:summary].should == 'c'
  # end

  # it "returns that it has failed" do
  #   ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)

  #   Flapjack.redis.hset("check:#{name}:#{check}", 'state', 'warning')
  #   ec.should be_failed

  #   Flapjack.redis.hset("check:#{name}:#{check}", 'state', 'critical')
  #   ec.should be_failed

  #   Flapjack.redis.hset("check:#{name}:#{check}", 'state', 'unknown')
  #   ec.should be_failed
  # end

  # it "returns that it has not failed" do
  #   ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)

  #   Flapjack.redis.hset("check:#{name}:#{check}", 'state', 'ok')
  #   ec.should_not be_failed

  #   Flapjack.redis.hset("check:#{name}:#{check}", 'state', 'acknowledgement')
  #   ec.should_not be_failed
  # end

  # it "returns a status summary" do
  #   ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)

  #   t = Time.now.to_i
  #   ec.update_state('ok', :timestamp => time_before(t, 5), :summary => 'a')
  #   ec.update_state('critical', :timestamp => time_before(t, 4), :summary => 'b')
  #   ec.update_state('ok', :timestamp => time_before(t, 3), :summary => 'c')
  #   ec.update_state('critical', :timestamp => time_before(t, 2), :summary => 'd')

  #   summary = ec.summary
  #   summary.should == 'd'
  # end

  # it "returns timestamps for its last notifications" do
  #   t = Time.now.to_i
  #   Flapjack.redis.set("#{name}:#{check}:last_problem_notification", t - 30)
  #   Flapjack.redis.set("#{name}:#{check}:last_acknowledgement_notification", t - 15)
  #   Flapjack.redis.set("#{name}:#{check}:last_recovery_notification", t)

  #   ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
  #   ec.last_notification_for_state(:problem)[:timestamp].should == t - 30
  #   ec.last_notification_for_state(:acknowledgement)[:timestamp].should == t - 15
  #   ec.last_notification_for_state(:recovery)[:timestamp].should == t
  # end

  # it "finds all related contacts" do
  #   ec = Flapjack::Data::EntityCheck.for_entity_name(name, check)
  #   contacts = ec.contacts
  #   contacts.should_not be_nil
  #   contacts.should be_an(Array)
  #   contacts.should have(1).contact
  #   contacts.first.name.should == 'John Johnson'
  # end

  # it "generates ephemeral tags for itself" do
  #   ec = Flapjack::Data::EntityCheck.for_entity_name('foo-app-01.example.com', 'Disk / Utilisation')
  #   tags = ec.tags
  #   tags.should_not be_nil
  #   tags.should be_a(Flapjack::Data::TagSet)
  #   ['foo-app-01', 'example.com', 'disk', '/', 'utilisation'].to_set.subset?(tags).should be_true
  # end

end
