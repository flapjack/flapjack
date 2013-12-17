require 'spec_helper'
require 'flapjack/processor'
require 'flapjack/coordinator'

describe Flapjack::Processor, :logger => true do

  # NB: this is only testing the public API of the Processor class, which is pretty limited.
  # (initialize, main, stop). Most test coverage for this class comes from the cucumber features.

  let(:lock) { double(Monitor) }
  let(:redis) { double(Redis) }

  before(:each) do
    allow(Flapjack).to receive(:redis).and_return(redis)
  end

  # TODO this does too much -- split it up
  it "starts up, runs and shuts down" do
    t = Time.now.to_i

    expect(Flapjack::Filters::Ok).to receive(:new)
    expect(Flapjack::Filters::ScheduledMaintenance).to receive(:new)
    expect(Flapjack::Filters::UnscheduledMaintenance).to receive(:new)
    expect(Flapjack::Filters::Delays).to receive(:new)
    expect(Flapjack::Filters::Acknowledgement).to receive(:new)

    expect(redis).to receive(:hset).with(/^executive_instance:/, "boot_time", anything)
    expect(redis).to receive(:hget).with('event_counters', 'all').and_return(nil)
    expect(redis).to receive(:hset).with('event_counters', 'all', 0)
    expect(redis).to receive(:hset).with('event_counters', 'ok', 0)
    expect(redis).to receive(:hset).with('event_counters', 'failure', 0)
    expect(redis).to receive(:hset).with('event_counters', 'action', 0)

    expect(redis).to receive(:hset).with(/^event_counters:/, 'all', 0)
    expect(redis).to receive(:hset).with(/^event_counters:/, 'ok', 0)
    expect(redis).to receive(:hset).with(/^event_counters:/, 'failure', 0)
    expect(redis).to receive(:hset).with(/^event_counters:/, 'action', 0)

    expect(redis).to receive(:expire).with(/^executive_instance:/, anything)
    expect(redis).to receive(:expire).with(/^event_counters:/, anything).exactly(4).times

    # redis.should_receive(:hincrby).with('event_counters', 'all', 1)
    # redis.should_receive(:hincrby).with(/^event_counters:/, 'all', 1)

    expect(lock).to receive(:synchronize).and_yield

    processor = Flapjack::Processor.new(:lock => lock, :config => {}, :logger => @logger)

    expect(Flapjack::Data::Event).to receive(:foreach_on_queue)
    expect(Flapjack::Data::Event).to receive(:wait_for_queue).and_raise(Flapjack::PikeletStop)

    expect { processor.start }.to raise_error(Flapjack::PikeletStop)
  end

  it "starts up, runs and shuts down everything when queue empty" do
    t = Time.now.to_i

    expect(Flapjack::Filters::Ok).to receive(:new)
    expect(Flapjack::Filters::ScheduledMaintenance).to receive(:new)
    expect(Flapjack::Filters::UnscheduledMaintenance).to receive(:new)
    expect(Flapjack::Filters::Delays).to receive(:new)
    expect(Flapjack::Filters::Acknowledgement).to receive(:new)

    expect(redis).to receive(:hset).with(/^executive_instance:/, "boot_time", anything)
    expect(redis).to receive(:hget).with('event_counters', 'all').and_return(nil)
    expect(redis).to receive(:hset).with('event_counters', 'all', 0)
    expect(redis).to receive(:hset).with('event_counters', 'ok', 0)
    expect(redis).to receive(:hset).with('event_counters', 'failure', 0)
    expect(redis).to receive(:hset).with('event_counters', 'action', 0)

    expect(redis).to receive(:hset).with(/^event_counters:/, 'all', 0)
    expect(redis).to receive(:hset).with(/^event_counters:/, 'ok', 0)
    expect(redis).to receive(:hset).with(/^event_counters:/, 'failure', 0)
    expect(redis).to receive(:hset).with(/^event_counters:/, 'action', 0)

    expect(redis).to receive(:expire).with(/^executive_instance:/, anything)
    expect(redis).to receive(:expire).with(/^event_counters:/, anything).exactly(4).times

    # redis.should_receive(:hincrby).with('event_counters', 'all', 1)
    # redis.should_receive(:hincrby).with(/^event_counters:/, 'all', 1)

    expect(lock).to receive(:synchronize).and_yield

    processor = Flapjack::Processor.new(:lock => lock,
      :config => {'exit_on_queue_empty' => true}, :logger => @logger)

    expect(Flapjack::Data::Event).to receive(:foreach_on_queue)
    expect(Flapjack::Data::Event).not_to receive(:wait_for_queue)

    expect { processor.start }.to raise_error(Flapjack::GlobalStop)
  end

end
