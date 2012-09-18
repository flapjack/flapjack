require 'spec_helper'

require 'yajl/json_gem'

require 'flapjack/data/entity'
require 'flapjack/data/entity_check'

describe Flapjack::Data::EntityCheck, :redis => true do

  let(:name)  { 'abc-123' }
  let(:check) { 'ping' }

  let(:half_an_hour) { 30 * 60 }

  before(:each) do
    Flapjack::Data::Entity.add({'id'   => '5000',
                                'name' => name},
                               :redis => @redis)
  end

  it "is created for an event id" do
    ec = Flapjack::Data::EntityCheck.for_event_id("#{name}:ping", :redis => @redis)
    ec.should_not be_nil
    ec.entity.should_not be_nil
    ec.entity.name.should_not be_nil
    ec.entity.name.should == name
    ec.check.should_not be_nil
    ec.check.should == 'ping'
  end

  it "is created for an entity name" do
    ec = Flapjack::Data::EntityCheck.for_entity_name(name, 'ping', :redis => @redis)
    ec.should_not be_nil
    ec.entity.should_not be_nil
    ec.entity.name.should_not be_nil
    ec.entity.name.should == name
    ec.check.should_not be_nil
    ec.check.should == 'ping'
  end

  it "is created for an entity id" do
    ec = Flapjack::Data::EntityCheck.for_entity_id(5000, 'ping', :redis => @redis)
    ec.should_not be_nil
    ec.entity.should_not be_nil
    ec.entity.name.should_not be_nil
    ec.entity.name.should == name
    ec.check.should_not be_nil
    ec.check.should == 'ping'
  end

  it "is created for an entity object" do
    e = Flapjack::Data::Entity.find_by_name(name, :redis => @redis)
    ec = Flapjack::Data::EntityCheck.for_entity(e, 'ping', :redis => @redis)
    ec.should_not be_nil
    ec.entity.should_not be_nil
    ec.entity.name.should_not be_nil
    ec.entity.name.should == name
    ec.check.should_not be_nil
    ec.check.should == 'ping'
  end

  it "is not created for a missing entity" do
    expect {
      Flapjack::Data::EntityCheck.for_entity(nil, 'ping', :redis => @redis)
    }.to raise_error
  end

  it "raises an error if not created with a redis connection handle" do
    expect {
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, 'ping')
    }.to raise_error
  end

  context "maintenance" do

    it "returns that it is in unscheduled maintenance" do
      @redis.set("#{name}:#{check}:unscheduled_maintenance", Time.now.to_i.to_s)

      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
      ec.should be_in_unscheduled_maintenance
    end

    it "returns that it is not in unscheduled maintenance" do
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
      ec.should_not be_in_unscheduled_maintenance
    end

    it "returns that it is in scheduled maintenance" do
      @redis.set("#{name}:#{check}:scheduled_maintenance", Time.now.to_i.to_s)

      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
      ec.should be_in_scheduled_maintenance
    end

    it "returns that it is not in scheduled maintenance" do
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
      ec.should_not be_in_scheduled_maintenance
    end

    it "creates an unscheduled maintenance period" do
      t = Time.now.to_i
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
      ec.create_unscheduled_maintenance(:start_time => t, :duration => half_an_hour, :summary => 'oops')

      timestamp = @redis.get("#{name}:#{check}:unscheduled_maintenance")
      timestamp.should_not be_nil
      timestamp.should == t.to_s

      umps = @redis.zrange("#{name}:#{check}:unscheduled_maintenances", 0, -1, :with_scores => true)
      umps.should_not be_nil
      umps.should be_an(Array)
      umps.should have(1).unscheduled_maintenance_period
      umps[0].should be_an(Array)

      start_time = umps[0][0]
      start_time.should_not be_nil
      start_time.should be_a(String)
      start_time.should == t.to_s

      score = umps[0][1]
      score.should_not be_nil
      score.should be_a(Float)
      score.should == half_an_hour

      summary = @redis.get("#{name}:#{check}:#{t}:unscheduled_maintenance:summary")
      summary.should_not be_nil
      summary.should == 'oops'
    end

    it "creates a scheduled maintenance period for a future time" do
      t = Time.now.to_i
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
      ec.create_scheduled_maintenance(:start_time => t + (60 * 60),
        :duration => half_an_hour, :summary => "30 minutes")

      smps = @redis.zrange("#{name}:#{check}:scheduled_maintenances", 0, -1, :with_scores => true)
      smps.should_not be_nil
      smps.should be_an(Array)
      smps.should have(1).scheduled_maintenance_period
      smps[0].should be_an(Array)

      start_time = smps[0][0]
      start_time.should_not be_nil
      start_time.should be_a(String)
      start_time.should == (t + (60 * 60)).to_s

      score = smps[0][1]
      score.should_not be_nil
      score.should be_a(Float)
      score.should == half_an_hour
    end

    it "creates a scheduled maintenance period covering the current time"

    it "removes a scheduled maintenance period for a future time"

    it "removes a scheduled maintenance period covering a current time"

    it "returns a list of scheduled maintenance periods" do
      t = Time.now.to_i
      five_hours_ago = t - (60 * 60 * 5)
      three_hours_ago = t - (60 * 60 * 3)

      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
      ec.create_scheduled_maintenance(:start_time => five_hours_ago,
        :duration => half_an_hour, :summary => "first")
      ec.create_scheduled_maintenance(:start_time => three_hours_ago,
        :duration => half_an_hour, :summary => "second")

      smp = ec.maintenances(nil, nil, :scheduled => true)
      smp.should_not be_nil
      smp.should be_an(Array)
      smp.should have(2).scheduled_maintenance_periods
      smp[0].should == {:start_time => five_hours_ago,
                        :end_time   => five_hours_ago + half_an_hour,
                        :duration   => half_an_hour,
                        :summary    => "first"}
      smp[1].should == {:start_time => three_hours_ago,
                        :end_time   => three_hours_ago + half_an_hour,
                        :duration   => half_an_hour,
                        :summary    => "second"}
    end

    it "returns a list of unscheduled maintenance periods" do
      t = Time.now.to_i
      five_hours_ago = t - (60 * 60 * 5)
      three_hours_ago = t - (60 * 60 * 3)

      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
      ec.create_unscheduled_maintenance(:start_time => five_hours_ago,
        :duration => half_an_hour, :summary => "first")
      ec.create_unscheduled_maintenance(:start_time => three_hours_ago,
        :duration => half_an_hour, :summary => "second")

      ump =  ec.maintenances(nil, nil, :scheduled => false)
      ump.should_not be_nil
      ump.should be_an(Array)
      ump.should have(2).unscheduled_maintenance_periods
      ump[0].should == {:start_time => five_hours_ago,
                        :end_time   => five_hours_ago + half_an_hour,
                        :duration   => half_an_hour,
                        :summary    => "first"}
      ump[1].should == {:start_time => three_hours_ago,
                        :end_time   => three_hours_ago + half_an_hour,
                        :duration   => half_an_hour,
                        :summary    => "second"}
    end

    it "updates scheduled maintenance periods"

  end

  it "creates an event" do
    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
    t = Time.now.to_i
    ec.create_event('type'    => 'service',
                    'state'   => 'ok',
                    'summary' => 'everything checked out',
                    'time'    => t)
    event_json = @redis.rpop('events')
    event_json.should_not be_nil
    event = nil
    expect {
      event = JSON.parse(event_json)
    }.not_to raise_error
    event.should_not be_nil
    event.should be_a(Hash)
    event.should == {
      'entity'  => name,
      'check'   => check,
      'type'    => 'service',
      'state'   => 'ok',
      'summary' => 'everything checked out',
      'time'    => t
    }
  end

  it "creates an acknowledgement" do
    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
    t = Time.now.to_i
    ec.create_acknowledgement('summary'            => 'looking now',
                              'time'               => t,
                              'acknowledgement_id' => '75')
    event_json = @redis.rpop('events')
    event_json.should_not be_nil
    event = nil
    expect {
      event = JSON.parse(event_json)
    }.not_to raise_error
    event.should_not be_nil
    event.should be_a(Hash)
    event.should == {
      'entity'             => name,
      'check'              => check,
      'type'               => 'action',
      'state'              => 'acknowledgement',
      'summary'            => 'looking now',
      'time'               => t,
      'acknowledgement_id' => '75',
    }
  end

  it "returns its state" do
    @redis.hset("check:#{name}:#{check}", 'state', 'ok')

    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
    state = ec.state
    state.should_not be_nil
    state.should == 'ok'
  end

  it "updates state" do
    @redis.hset("check:#{name}:#{check}", 'state', 'ok')

    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
    ec.update_state('critical')

    state = @redis.hget("check:#{name}:#{check}", 'state')
    state.should_not be_nil
    state.should == 'critical'
  end

  it "does not update state with invalid value" do
    @redis.hset("check:#{name}:#{check}", 'state', 'ok')

    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
    ec.update_state('silly')

    state = @redis.hget("check:#{name}:#{check}", 'state')
    state.should_not be_nil
    state.should == 'ok'
  end

  def time_before(t, min, sec = 0)
    t - ((60 * min) + sec)
  end

  it "returns a list of historical states for a time range" do
    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)

    t = Time.now.to_i
    ec.update_state('ok', :timestamp => time_before(t, 5), :summary => 'a')
    ec.update_state('critical', :timestamp => time_before(t, 4), :summary => 'b')
    ec.update_state('ok', :timestamp => time_before(t, 3), :summary => 'c')
    ec.update_state('critical', :timestamp => time_before(t, 2), :summary => 'd')
    ec.update_state('ok', :timestamp => time_before(t, 1), :summary => 'e')

    states = ec.historical_states(time_before(t, 4), t)
    states.should_not be_nil
    states.should be_an(Array)
    states.should have(4).data_hashes
    states[0][:summary].should == 'b'
    states[1][:summary].should == 'c'
    states[2][:summary].should == 'd'
    states[3][:summary].should == 'e'
  end

  it "returns a list of historical unscheduled maintenances for a time range" do
    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)

    t = Time.now.to_i
    # ec.update_state('ok', :timestamp => time_before(t, 5), :summary => 'a')
    # ec.update_state('critical', :timestamp => time_before(t, 4), :summary => 'b')
    # ec.update_state('ok', :timestamp => time_before(t, 3), :summary => 'c')
    # ec.update_state('critical', :timestamp => time_before(t, 2), :summary => 'd')
    # ec.update_state('ok', :timestamp => time_before(t, 1), :summary => 'e')

    # states = ec.historical_states(time_before(t, 4), t)
    # states.should_not be_nil
    # states.should be_an(Array)
    # states.should have(4).data_hashes
    # states[0][:summary].should == 'b'
    # states[1][:summary].should == 'c'
    # states[2][:summary].should == 'd'
    # states[3][:summary].should == 'e'
  end

  it "returns a list of historical scheduled maintenances for a time range" do
    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)

    t = Time.now.to_i

    ec.create_scheduled_maintenance(:start_time => time_before(t, 180),
      :duration => half_an_hour, :summary => "a")
    ec.create_scheduled_maintenance(:start_time => time_before(t, 120),
      :duration => half_an_hour, :summary => "b")
    ec.create_scheduled_maintenance(:start_time => time_before(t, 60),
      :duration => half_an_hour, :summary => "c")

    sched_maint_periods = ec.maintenances(time_before(t, 150), t,
      :scheduled => true)
    sched_maint_periods.should_not be_nil
    sched_maint_periods.should be_an(Array)
    sched_maint_periods.should have(2).data_hashes
    sched_maint_periods[0][:summary].should == 'b'
    sched_maint_periods[1][:summary].should == 'c'
  end

  it "returns that it has failed" do
    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)

    @redis.hset("check:#{name}:#{check}", 'state', 'warning')
    ec.should be_failed

    @redis.hset("check:#{name}:#{check}", 'state', 'critical')
    ec.should be_failed
  end

  it "returns that it has not failed" do
    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)

    @redis.hset("check:#{name}:#{check}", 'state', 'ok')
    ec.should_not be_failed

    @redis.hset("check:#{name}:#{check}", 'state', 'acknowledgement')
    ec.should_not be_failed

    @redis.hset("check:#{name}:#{check}", 'state', 'unknown')
    ec.should_not be_failed
  end

  it "returns a status summary"

  it "returns timestamps for its last notifications" do
    t = Time.now.to_i
    @redis.set("#{name}:#{check}:last_problem_notification", t - 30)
    @redis.set("#{name}:#{check}:last_acknowledgement_notification", t - 15)
    @redis.set("#{name}:#{check}:last_recovery_notification", t)

    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
    ec.last_problem_notification.should == t - 30
    ec.last_acknowledgement_notification.should == t - 15
    ec.last_recovery_notification.should == t
  end

end