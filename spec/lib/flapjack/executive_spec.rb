require 'spec_helper'
require 'flapjack/executive'

describe Flapjack::Executive, :logger => true do

  # NB: this is only testing the public API of the Executive class, which is pretty limited.
  # (initialize, main, stop). Most test coverage for this class comes from the cucumber features.

  # TODO this does too much -- split it up
  it "starts up, runs and shuts down" do
    t = Time.now.to_i

    Flapjack::Filters::Ok.should_receive(:new)
    Flapjack::Filters::ScheduledMaintenance.should_receive(:new)
    Flapjack::Filters::UnscheduledMaintenance.should_receive(:new)
    Flapjack::Filters::DetectMassClientFailures.should_receive(:new)
    Flapjack::Filters::Delays.should_receive(:new)
    Flapjack::Filters::Acknowledgement.should_receive(:new)

    redis = mock('redis')

    redis.should_receive(:set).with('boot_time', a_kind_of(Integer))
    redis.should_receive(:hget).with('event_counters', 'all').and_return(nil)
    redis.should_receive(:hset).with('event_counters', 'all', 0)
    redis.should_receive(:hset).with('event_counters', 'ok', 0)
    redis.should_receive(:hset).with('event_counters', 'failure', 0)
    redis.should_receive(:hset).with('event_counters', 'action', 0)

    redis.should_receive(:zadd).with('executive_instances', a_kind_of(Integer), a_kind_of(String))
    redis.should_receive(:hset).with(/^event_counters:/, 'all', 0)
    redis.should_receive(:hset).with(/^event_counters:/, 'ok', 0)
    redis.should_receive(:hset).with(/^event_counters:/, 'failure', 0)
    redis.should_receive(:hset).with(/^event_counters:/, 'action', 0)

    redis.should_receive(:hincrby).with('event_counters', 'all', 1)
    redis.should_receive(:hincrby).with(/^event_counters:/, 'all', 1)

    Flapjack::Data::Event.should_receive(:pending_count).with(:redis => redis).and_return(0)

    Flapjack::RedisPool.should_receive(:new).and_return(redis)
    executive = Flapjack::Executive.new(:config => {}, :logger => @logger)

    shutdown_evt = mock(Flapjack::Data::Event)
    shutdown_evt.should_receive(:inspect)
    shutdown_evt.should_receive(:id).and_return('-:-')
    shutdown_evt.should_receive(:type).exactly(3).times.and_return('shutdown')
    shutdown_evt.should_receive(:state).and_return(nil)
    shutdown_evt.should_receive(:summary).and_return(nil)
    shutdown_evt.should_receive(:time).and_return(Time.now)
    Flapjack::Data::Event.should_receive(:next) {
      executive.instance_variable_set('@should_quit', true)
      shutdown_evt
    }

    executive.start
  end

end
