require 'spec_helper'
require 'flapjack/processor'
require 'flapjack/coordinator'

describe Flapjack::Processor, :logger => true do

  # NB: this is only testing the public API of the Processor class, which is pretty limited.
  # (initialize, main, stop). Most test coverage for this class comes from the cucumber features.

  let(:lock)  { double(Monitor) }
  let(:redis) { double(Redis) }
  let(:multi) { double('multi') }

  before(:each) do
    allow(Flapjack).to receive(:redis).and_return(redis)
  end

  def expect_filters
    expect(Flapjack::Filters::Ok).to receive(:new)
    expect(Flapjack::Filters::ScheduledMaintenance).to receive(:new)
    expect(Flapjack::Filters::UnscheduledMaintenance).to receive(:new)
    expect(Flapjack::Filters::Delays).to receive(:new)
    expect(Flapjack::Filters::Acknowledgement).to receive(:new)
  end

  def expect_counters
    expect(redis).to receive(:hmget).with('event_counters', 'all', 'ok', 'failure', 'action', 'invalid').and_return([nil, nil, nil, nil])

    expect(redis).to receive(:multi).and_yield(multi)
    expect(multi).to receive(:hset).with(/^executive_instance:/, "boot_time", anything)
    expect(multi).to receive(:hset).with('event_counters', 'all', 0)
    expect(multi).to receive(:hset).with('event_counters', 'ok', 0)
    expect(multi).to receive(:hset).with('event_counters', 'failure', 0)
    expect(multi).to receive(:hset).with('event_counters', 'action', 0)
    expect(multi).to receive(:hset).with('event_counters', 'invalid', 0)

    expect(multi).to receive(:hmset).with(/^event_counters:/, 'all', 0, 'ok', 0, 'failure', 0, 'action', 0, 'invalid', 0)
    expect(multi).to receive(:zadd).with('executive_instances', 0, an_instance_of(String))
    expect(multi).to receive(:expire).with(/^executive_instance:/, anything)
    expect(multi).to receive(:expire).with(/^event_counters:/, anything)
  end

  def expect_counters_invalid
    expect(multi).to receive(:hincrby).with('event_counters', 'all', 1)
    expect(multi).to receive(:hincrby).with(/^event_counters:/, 'all', 1)

    expect(multi).to receive(:hincrby).with('event_counters', 'invalid', 1)
    expect(multi).to receive(:hincrby).with(/^event_counters:/, 'invalid', 1)
  end

  it "starts up, runs and shuts down (archiving, accepted)" do
    expect_filters
    expect_counters

    expect(lock).to receive(:synchronize).and_yield

    processor = Flapjack::Processor.new(:lock => lock,
      :config => {'queue' => 'events', 'archive_events' => true,
        'events_archive_maxage' => 3000})

    event_json = double('event_json')
    event_data = double(event_data)
    event = double(Flapjack::Data::Event)

    expect(redis).to receive(:rpoplpush).with('events', /^events_archive:/).twice.and_return(event_json, nil)
    expect(redis).to receive(:expire).with(/^events_archive:/, kind_of(Integer))

    expect(Flapjack::Data::Event).to receive(:parse_and_validate).
      with(event_json).and_return([event_data, []])
    expect(Flapjack::Data::Event).to receive(:new).with(event_data).and_return(event)
    expect(redis).to receive(:brpop).with('events_actions').and_raise(Flapjack::PikeletStop)
    expect(redis).to receive(:quit)

    # TODO spec actual functionality
    expect(processor).to receive(:process_event).with(event)

    expect { processor.start }.to raise_error(Flapjack::PikeletStop)
  end

  it "starts up, runs and shuts down (archiving, rejected)" do
    expect_filters
    expect_counters
    expect_counters_invalid

    expect(lock).to receive(:synchronize).and_yield

    processor = Flapjack::Processor.new(:lock => lock,
      :config => {'queue' => 'events', 'archive_events' => true,
        'events_archive_maxage' => 3000})

    event_json = double('event_json')

    expect(redis).to receive(:rpoplpush).with('events', /^events_archive:/).twice.and_return(event_json, nil)
    expect(redis).to receive(:multi).and_yield(multi)
    expect(multi).to receive(:lrem).with(/^events_archive:/, 1, event_json)
    expect(multi).to receive(:lpush).with(/^events_rejected:/, event_json)
    expect(multi).to receive(:expire).with(/^events_archive:/, kind_of(Integer))

    expect(Flapjack::Data::Event).to receive(:parse_and_validate).
      with(event_json).and_return([nil, ["error"]])
    expect(Flapjack::Data::Event).not_to receive(:new)
    expect(redis).to receive(:brpop).with('events_actions').and_raise(Flapjack::PikeletStop)
    expect(redis).to receive(:quit)

    expect(processor).not_to receive(:process_event)

    expect { processor.start }.to raise_error(Flapjack::PikeletStop)
  end

  it "starts up, runs and shuts down (not archiving, accepted)" do
    expect_filters
    expect_counters

    expect(lock).to receive(:synchronize).and_yield

    processor = Flapjack::Processor.new(:lock => lock, :config => {'queue' => 'events'})

    event_json = double('event_json')
    event_data = double(event_data)
    event = double(Flapjack::Data::Event)

    expect(redis).to receive(:rpop).with('events').twice.and_return(event_json, nil)
    expect(Flapjack::Data::Event).to receive(:parse_and_validate).
      with(event_json).and_return([event_data, []])
    expect(Flapjack::Data::Event).to receive(:new).with(event_data).and_return(event)
    expect(redis).to receive(:brpop).with('events_actions').and_raise(Flapjack::PikeletStop)
    expect(redis).to receive(:quit)

    # TODO spec actual functionality
    expect(processor).to receive(:process_event).with(event)

    expect { processor.start }.to raise_error(Flapjack::PikeletStop)
  end

  it "starts up, runs and shuts down (not archiving, rejected)" do
    expect_filters
    expect_counters
    expect_counters_invalid

    expect(lock).to receive(:synchronize).and_yield

    processor = Flapjack::Processor.new(:lock => lock,
      :config => {'queue' => 'events'})

    event_json = double('event_json')

    expect(redis).to receive(:rpop).with('events').twice.and_return(event_json, nil)
    expect(Flapjack::Data::Event).to receive(:parse_and_validate).
      with(event_json).and_return([nil, ["error"]])
    expect(Flapjack::Data::Event).not_to receive(:new)
    expect(redis).to receive(:multi).and_yield(multi)
    expect(multi).to receive(:lpush).with(/^events_rejected:/, event_json)
    expect(redis).to receive(:brpop).with('events_actions').and_raise(Flapjack::PikeletStop)
    expect(redis).to receive(:quit)

    expect(processor).not_to receive(:process_event)

    expect { processor.start }.to raise_error(Flapjack::PikeletStop)
  end

  it "starts up, runs and shuts down everything when queue empty (not archiving, accepted)" do
    expect_filters
    expect_counters

    expect(lock).to receive(:synchronize).and_yield

    processor = Flapjack::Processor.new(:lock => lock,
      :config => {'queue' => 'events', 'exit_on_queue_empty' => true})

    event_json = double('event_json')
    event_data = double(event_data)
    event = double(Flapjack::Data::Event)

    expect(redis).to receive(:rpop).with('events').twice.and_return(event_json, nil)
    expect(Flapjack::Data::Event).to receive(:parse_and_validate).
      with(event_json).and_return([event_data, []])
    expect(Flapjack::Data::Event).to receive(:new).with(event_data).and_return(event)
    expect(redis).to receive(:quit)

    # TODO spec actual functionality
    expect(processor).to receive(:process_event).with(event)

    expect { processor.start }.to raise_error(Flapjack::GlobalStop)
  end

#   it "rejects invalid event JSON (archiving)" do
#     bad_event_json = '{{{'
#     expect(redis).to receive(:rpoplpush).
#       with('events', /^events_archive:/).and_return(bad_event_json, nil)
#     expect(redis).to receive(:multi)
#     expect(redis).to receive(:lrem).with(/^events_archive:/, 1, bad_event_json)
#     expect(redis).to receive(:lpush).with(/^events_rejected:/, bad_event_json)
#     expect(redis).to receive(:exec)
#     expect(redis).to receive(:expire)

#     Flapjack::Data::Event.foreach_on_queue('events', :archive_events => true) {|result|
#       expect(result).to be_nil
#     }
#   end

#   it "rejects invalid event JSON (not archiving)" do
#     bad_event_json = '{{{'
#     expect(redis).to receive(:rpop).with('events').
#       and_return(bad_event_json, nil)
#     expect(redis).to receive(:lpush).with(/^events_rejected:/, bad_event_json)

#     Flapjack::Data::Event.foreach_on_queue('events', :archive_events => false) {|result|
#       expect(result).to be_nil
#     }
#   end

end
