require 'spec_helper'
require 'flapjack/processor'

describe Flapjack::Processor, :logger => true do

  # NB: this is only testing the public API of the Processor class, which is pretty limited.
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

    redis.should_receive(:hset).with(/^executive_instance:/, "boot_time", anything)
    redis.should_receive(:hget).with('event_counters', 'all').and_return(nil)
    redis.should_receive(:hset).with('event_counters', 'all', 0)
    redis.should_receive(:hset).with('event_counters', 'ok', 0)
    redis.should_receive(:hset).with('event_counters', 'failure', 0)
    redis.should_receive(:hset).with('event_counters', 'action', 0)

    redis.should_receive(:hset).with(/^event_counters:/, 'all', 0)
    redis.should_receive(:hset).with(/^event_counters:/, 'ok', 0)
    redis.should_receive(:hset).with(/^event_counters:/, 'failure', 0)
    redis.should_receive(:hset).with(/^event_counters:/, 'action', 0)

    redis.should_receive(:expire).with(/^executive_instance:/, anything)
    redis.should_receive(:expire).with(/^event_counters:/, anything).exactly(4).times

    # redis.should_receive(:hincrby).with('event_counters', 'all', 1)
    # redis.should_receive(:hincrby).with(/^event_counters:/, 'all', 1)

    Flapjack::Data::Event.should_receive(:pending_count).with(:redis => redis).and_return(0)

    Flapjack::RedisPool.should_receive(:new).and_return(redis)
    executive = Flapjack::Processor.new(:config => {}, :logger => @logger)

    shutdown_evt = mock(Flapjack::Data::Event)
    shutdown_evt.should_receive(:inspect)
    shutdown_evt.should_receive(:type).and_return('shutdown')
    Flapjack::Data::Event.should_receive(:next) {
      executive.instance_variable_set('@should_quit', true)
      shutdown_evt
    }

    executive.start
  end

end
