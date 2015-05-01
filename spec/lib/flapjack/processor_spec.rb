require 'spec_helper'
require 'flapjack/processor'
require 'flapjack/coordinator'

describe Flapjack::Processor, :logger => true do

  # NB: this is only testing the public API of the Processor class, which is pretty limited.
  # (initialize, main, stop). Most test coverage for this class comes from the cucumber features.

  let(:lock)  { double(Monitor) }
  let(:redis) { double(Redis) }
  let(:multi) { double('multi') }

  let(:boot_time) { double(Time) }

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

  let(:global_stats)   { double(Flapjack::Data::Statistic) }
  let(:instance_stats) { double(Flapjack::Data::Statistic) }

  def expect_counters
    all_global = double('all_global', :all => [global_stats])
    expect(Flapjack::Data::Statistic).to receive(:intersect).
      with(:instance_name => 'global').and_return(all_global)

    expect(Flapjack::Data::Statistic).to receive(:new).
      with(:created_at => boot_time,
           :all_events => 0, :ok_events => 0,
           :failure_events => 0, :action_events => 0,
           :invalid_events => 0, :instance_name => an_instance_of(String)).
      and_return(instance_stats)
  end

  def expect_counters_invalid
    [global_stats, instance_stats].each do |stats|
      ['all', 'invalid'].each do |event_type|
        expect(stats).to receive("#{event_type}_events".to_sym).and_return(0)
        expect(stats).to receive("#{event_type}_events=".to_sym).with(1)
      end
    end
  end

  it "starts up, runs and shuts down (archiving, accepted)" do
    expect_filters
    expect_counters

    expect(lock).to receive(:synchronize).and_yield

    processor = Flapjack::Processor.new(:lock => lock,
      :config => {'queue' => 'events', 'archive_events' => true,
        'events_archive_maxage' => 3000}, :boot_time => boot_time)

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

    expect(instance_stats).to receive(:save!)
    expect(instance_stats).to receive(:persisted?).and_return(true)
    expect(instance_stats).to receive(:destroy)

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
        'events_archive_maxage' => 3000}, :boot_time => boot_time)

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

    expect(Flapjack::Data::Statistic).to receive(:lock).and_yield
    expect(global_stats).to receive(:save!)
    expect(instance_stats).to receive(:save!).twice
    expect(instance_stats).to receive(:persisted?).and_return(true)
    expect(instance_stats).to receive(:destroy)

    expect(processor).not_to receive(:process_event)

    expect { processor.start }.to raise_error(Flapjack::PikeletStop)
  end

  it "starts up, runs and shuts down (not archiving, accepted)" do
    expect_filters
    expect_counters

    expect(lock).to receive(:synchronize).and_yield

    processor = Flapjack::Processor.new(:lock => lock, :config => {'queue' => 'events'},
      :boot_time => boot_time)

    event_json = double('event_json')
    event_data = double(event_data)
    event = double(Flapjack::Data::Event)

    expect(redis).to receive(:rpop).with('events').twice.and_return(event_json, nil)
    expect(Flapjack::Data::Event).to receive(:parse_and_validate).
      with(event_json).and_return([event_data, []])
    expect(Flapjack::Data::Event).to receive(:new).with(event_data).and_return(event)
    expect(redis).to receive(:brpop).with('events_actions').and_raise(Flapjack::PikeletStop)
    expect(redis).to receive(:quit)

    expect(instance_stats).to receive(:save!)
    expect(instance_stats).to receive(:persisted?).and_return(true)
    expect(instance_stats).to receive(:destroy)

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
      :config => {'queue' => 'events'}, :boot_time => boot_time)

    event_json = double('event_json')

    expect(redis).to receive(:rpop).with('events').twice.and_return(event_json, nil)
    expect(Flapjack::Data::Event).to receive(:parse_and_validate).
      with(event_json).and_return([nil, ["error"]])
    expect(Flapjack::Data::Event).not_to receive(:new)
    expect(redis).to receive(:multi).and_yield(multi)
    expect(multi).to receive(:lpush).with(/^events_rejected:/, event_json)
    expect(redis).to receive(:brpop).with('events_actions').and_raise(Flapjack::PikeletStop)
    expect(redis).to receive(:quit)

    expect(Flapjack::Data::Statistic).to receive(:lock).and_yield
    expect(global_stats).to receive(:save!)
    expect(instance_stats).to receive(:save!).twice
    expect(instance_stats).to receive(:persisted?).and_return(true)
    expect(instance_stats).to receive(:destroy)

    expect(processor).not_to receive(:process_event)

    expect { processor.start }.to raise_error(Flapjack::PikeletStop)
  end

  it "starts up, runs and shuts down everything when queue empty (not archiving, accepted)" do
    expect_filters
    expect_counters

    expect(lock).to receive(:synchronize).and_yield

    processor = Flapjack::Processor.new(:lock => lock,
      :config => {'queue' => 'events', 'exit_on_queue_empty' => true},
      :boot_time => boot_time)

    event_json = double('event_json')
    event_data = double(event_data)
    event = double(Flapjack::Data::Event)

    expect(redis).to receive(:rpop).with('events').twice.and_return(event_json, nil)
    expect(Flapjack::Data::Event).to receive(:parse_and_validate).
      with(event_json).and_return([event_data, []])
    expect(Flapjack::Data::Event).to receive(:new).with(event_data).and_return(event)
    expect(redis).to receive(:quit)

    expect(instance_stats).to receive(:save!)
    expect(instance_stats).to receive(:persisted?).and_return(true)
    expect(instance_stats).to receive(:destroy)

    # TODO spec actual functionality
    expect(processor).to receive(:process_event).with(event)

    expect { processor.start }.to raise_error(Flapjack::GlobalStop)
  end

  it "rejects invalid event JSON (archiving)" # do
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
