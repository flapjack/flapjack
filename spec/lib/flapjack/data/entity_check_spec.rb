require 'spec_helper'

require 'yajl/json_gem'

require 'flapjack/data/entity'
require 'flapjack/data/entity_check'

describe Flapjack::Data::EntityCheck, :redis => true do

  let(:name)  { 'abc-123' }
  let(:check) { 'ping' }

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
    ec = Flapjack::Data::EntityCheck.for_entity(nil, 'ping', :redis => @redis)
    ec.should be_nil
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

    it "creates a scheduled maintenance period"

    it "removes a scheduled maintenance period"

    it "returns a list of scheduled maintenance periods" do
      t = Time.now.to_i
      five_hours_ago = t - (60 * 60 * 5)
      three_hours_ago = t - (60 * 60 * 3)
      half_an_hour = 60 * 30

      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
      ec.create_scheduled_maintenance(:start_time => five_hours_ago,
        :duration => half_an_hour, :summary => "first")
      ec.create_scheduled_maintenance(:start_time => three_hours_ago,
        :duration => half_an_hour, :summary => "second")

      smp = ec.scheduled_maintenances
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
      ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
      smp = ec.unscheduled_maintenances
      pending # TODO
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
    ec.create_acknowledgement('summary' => 'looking now',
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
      'type'    => 'action',
      'state'   => 'acknowledgement',
      'summary' => 'looking now',
      'time'    => t
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
    ec.state = 'critical'

    state = @redis.hget("check:#{name}:#{check}", 'state')
    state.should_not be_nil
    state.should == 'critical'
  end

  it "does not update state with invalid date" do
    @redis.hset("check:#{name}:#{check}", 'state', 'ok')

    ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
    ec.state = 'silly'

    state = @redis.hget("check:#{name}:#{check}", 'state')
    state.should_not be_nil
    state.should == 'ok'
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

  it "returns a status hash" do

  end

  it "returns its last notifications"

  it "returns a status summary"

  it "returns duration of current failure"

  it "returns time since last problem alert"

  it "returns time since last alert about current problem"

end