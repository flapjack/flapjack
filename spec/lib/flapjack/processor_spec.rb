require 'spec_helper'
require 'flapjack/processor'
require 'flapjack/coordinator'

describe Flapjack::Processor, :logger => true do

  # NB: this is only testing the public API of the Processor class, which is pretty limited.
  # (initialize, main, stop). Most test coverage for this class comes from the cucumber features.

  let(:lock)  { double(Monitor) }
  let(:redis) { double(Redis) }

  before(:each) do
    allow(Flapjack).to receive(:redis).and_return(redis)
  end

  def expect_counters
    expect(redis).to receive(:multi)
    expect(redis).to receive(:hset).with(/^executive_instance:/, "boot_time", anything)
    expect(redis).to receive(:hget).with('event_counters', 'all').and_return(nil)
    expect(redis).to receive(:hmset).with('event_counters', 'all', 0, 'ok', 0, 'failure', 0, 'action', 0)
    expect(redis).to receive(:hmset).with(/^event_counters:/, 'all', 0, 'ok', 0, 'failure', 0, 'action', 0)

    expect(redis).to receive(:expire).with(/^executive_instance:/, anything)
    expect(redis).to receive(:expire).with(/^event_counters:/, anything)

    # redis.should_receive(:hincrby).with('event_counters', 'all', 1)
    # redis.should_receive(:hincrby).with(/^event_counters:/, 'all', 1)
    expect(redis).to receive(:exec)
  end

  it "starts up, runs and shuts down" do
    t = Time.now.to_i

    expect(Flapjack::Filters::Ok).to receive(:new)
    expect(Flapjack::Filters::ScheduledMaintenance).to receive(:new)
    expect(Flapjack::Filters::UnscheduledMaintenance).to receive(:new)
    expect(Flapjack::Filters::Delays).to receive(:new)
    expect(Flapjack::Filters::Acknowledgement).to receive(:new)

    expect_counters

    expect(lock).to receive(:synchronize).and_yield

    processor = Flapjack::Processor.new(:lock => lock, :config => {},
      :logger => @logger)

    # bad json, skips processing -- TODO rspec coverage of actual data
    expect(redis).to receive(:rpop).with('events').and_return("}", nil)
    expect(redis).to receive(:quit)
    expect(redis).to receive(:brpop).with('events_actions').and_raise(Flapjack::PikeletStop)

    expect { processor.start }.to raise_error(Flapjack::PikeletStop)
  end

  it "starts up, runs and shuts down everything when queue empty" do
    t = Time.now.to_i

    expect(Flapjack::Filters::Ok).to receive(:new)
    expect(Flapjack::Filters::ScheduledMaintenance).to receive(:new)
    expect(Flapjack::Filters::UnscheduledMaintenance).to receive(:new)
    expect(Flapjack::Filters::Delays).to receive(:new)
    expect(Flapjack::Filters::Acknowledgement).to receive(:new)

    expect_counters

    expect(lock).to receive(:synchronize).and_yield

    # bad json, skips processing -- TODO rspec coverage of actual data
    expect(redis).to receive(:rpop).with('events').and_return("}", nil)
    expect(redis).to receive(:quit)
    expect(redis).not_to receive(:brpop)

    processor = Flapjack::Processor.new(:lock => lock,
      :config => {'exit_on_queue_empty' => true}, :logger => @logger)

    expect { processor.start }.to raise_error(Flapjack::GlobalStop)
  end

  it "archives events when configured to"

end
