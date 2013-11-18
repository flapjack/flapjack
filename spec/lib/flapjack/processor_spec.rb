require 'spec_helper'
require 'flapjack/processor'
require 'flapjack/coordinator'

describe Flapjack::Processor, :logger => true do

  # NB: this is only testing the public API of the Processor class, which is pretty limited.
  # (initialize, main, stop). Most test coverage for this class comes from the cucumber features.

  let(:lock)  { double(Monitor) }
  let(:redis) { double(Redis) }

  before(:each) do
    Flapjack.stub(:redis).and_return(redis)
  end

  def expect_counters
    redis.should_receive(:multi)
    redis.should_receive(:hset).with(/^executive_instance:/, "boot_time", anything)
    redis.should_receive(:hget).with('event_counters', 'all').and_return(nil)
    redis.should_receive(:hmset).with('event_counters', 'all', 0, 'ok', 0, 'failure', 0, 'action', 0)
    redis.should_receive(:hmset).with(/^event_counters:/, 'all', 0, 'ok', 0, 'failure', 0, 'action', 0)

    redis.should_receive(:expire).with(/^executive_instance:/, anything)
    redis.should_receive(:expire).with(/^event_counters:/, anything)

    # redis.should_receive(:hincrby).with('event_counters', 'all', 1)
    # redis.should_receive(:hincrby).with(/^event_counters:/, 'all', 1)
    redis.should_receive(:exec)
  end

  it "starts up, runs and shuts down" do
    t = Time.now.to_i

    Flapjack::Filters::Ok.should_receive(:new)
    Flapjack::Filters::ScheduledMaintenance.should_receive(:new)
    Flapjack::Filters::UnscheduledMaintenance.should_receive(:new)
    Flapjack::Filters::Delays.should_receive(:new)
    Flapjack::Filters::Acknowledgement.should_receive(:new)

    expect_counters

    lock.should_receive(:synchronize).and_yield

    processor = Flapjack::Processor.new(:lock => lock, :config => {},
      :logger => @logger)

    # bad json, skips processing -- TODO rspec coverage of actual data
    redis.should_receive(:rpop).with('events').and_return("}", nil)
    redis.should_receive(:quit)
    redis.should_receive(:brpop).with('events_actions').and_raise(Flapjack::PikeletStop)

    expect { processor.start }.to raise_error(Flapjack::PikeletStop)
  end

  it "starts up, runs and shuts down everything when queue empty" do
    t = Time.now.to_i

    Flapjack::Filters::Ok.should_receive(:new)
    Flapjack::Filters::ScheduledMaintenance.should_receive(:new)
    Flapjack::Filters::UnscheduledMaintenance.should_receive(:new)
    Flapjack::Filters::Delays.should_receive(:new)
    Flapjack::Filters::Acknowledgement.should_receive(:new)

    expect_counters

    lock.should_receive(:synchronize).and_yield

    # bad json, skips processing -- TODO rspec coverage of actual data
    redis.should_receive(:rpop).with('events').and_return("}", nil)
    redis.should_receive(:quit)
    redis.should_not_receive(:brpop)

    processor = Flapjack::Processor.new(:lock => lock,
      :config => {'exit_on_queue_empty' => true}, :logger => @logger)

    expect { processor.start }.to raise_error(Flapjack::GlobalStop)
  end

  it "archives events when configured to"

end
