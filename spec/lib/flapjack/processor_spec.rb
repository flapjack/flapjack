require 'spec_helper'
require 'flapjack/processor'
require 'flapjack/coordinator'

describe Flapjack::Processor, :logger => true do

  # NB: this is only testing the public API of the Processor class, which is pretty limited.
  # (initialize, main, stop). Most test coverage for this class comes from the cucumber features.

  let(:config) { double(Flapjack::Configuration) }

  # TODO this does too much -- split it up
  it "starts up, runs and shuts down" do
    t = Time.now.to_i

    expect(Flapjack::Filters::Ok).to receive(:new)
    expect(Flapjack::Filters::ScheduledMaintenance).to receive(:new)
    expect(Flapjack::Filters::UnscheduledMaintenance).to receive(:new)
    expect(Flapjack::Filters::Delays).to receive(:new)
    expect(Flapjack::Filters::Acknowledgement).to receive(:new)

    redis = double('redis')

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

    expect(Flapjack::Data::Event).to receive(:pending_count).with('events', :redis => redis).and_return(0)

    expect(Flapjack::RedisPool).to receive(:new).and_return(redis)

    fc = double('coordinator')

    executive = Flapjack::Processor.new(:config => {}, :logger => @logger, :coordinator => fc)

    noop_evt = double(Flapjack::Data::Event)
    expect(noop_evt).to receive(:inspect)
    expect(noop_evt).to receive(:type).and_return('noop')
    expect(Flapjack::Data::Event).to receive(:next) {
      executive.instance_variable_set('@should_quit', true)
      noop_evt
    }

    begin
      executive.start
    rescue SystemExit
    end
  end

end
