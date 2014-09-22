require 'spec_helper'
require 'flapjack/data/event'

describe Flapjack::Data::Event do

  let(:entity_name) { 'xyz-example.com' }
  let(:check)       { 'ping' }
  let(:mock_redis)  { double(::Redis) }

  let!(:time) { Time.now}

  let(:event_data) { {'type'     => 'service',
                      'state'    => 'critical',
                      'entity'   => entity_name,
                      'check'    => check,
                      'time'     => time.to_i,
                      'summary'  => 'timeout',
                      'details'  => "couldn't access",
                      'perfdata' => "/=5504MB;5554;6348;0;7935",
                      'acknowledgement_id' => '1234',
                      'duration' => (60 * 60),
                      'tags'     => ['dev'] }
  }

  context 'class' do

    it "returns the next event (blocking, archiving)" do
      expect(mock_redis).to receive(:brpoplpush).
        with('events', /^events_archive:/, 0).and_return(event_data.to_json)
      expect(mock_redis).to receive(:expire)

      result = Flapjack::Data::Event.next('events', :block => true,
        :archive_events => true, :redis => mock_redis)
      expect(result).to be_an_instance_of(Flapjack::Data::Event)
    end

    it "returns the next event (blocking, not archiving)" do
      expect(mock_redis).to receive(:brpop).with('events', 0).
        and_return(['events', event_data.to_json])

      result = Flapjack::Data::Event.next('events',:block => true,
        :archive_events => false, :redis => mock_redis)
      expect(result).to be_an_instance_of(Flapjack::Data::Event)
    end

    it "returns the next event (non-blocking, archiving)" do
      expect(mock_redis).to receive(:rpoplpush).
        with('events', /^events_archive:/).and_return(event_data.to_json)
      expect(mock_redis).to receive(:expire)

      result = Flapjack::Data::Event.next('events', :block => false,
        :archive_events => true, :redis => mock_redis)
      expect(result).to be_an_instance_of(Flapjack::Data::Event)
    end

    it "returns the next event (non-blocking, not archiving)" do
      expect(mock_redis).to receive(:rpop).with('events').
        and_return(event_data.to_json)

      result = Flapjack::Data::Event.next('events', :block => false,
        :archive_events => false, :redis => mock_redis)
      expect(result).to be_an_instance_of(Flapjack::Data::Event)
    end

    it "rejects invalid event JSON (archiving)" do
      bad_event_json = '{{{'
      expect(mock_redis).to receive(:brpoplpush).
        with('events', /^events_archive:/, 0).and_return(bad_event_json)
      expect(mock_redis).to receive(:multi)
      expect(mock_redis).to receive(:lrem).with(/^events_archive:/, 1, bad_event_json)
      expect(mock_redis).to receive(:lpush).with(/^events_rejected:/, bad_event_json)
      expect(mock_redis).to receive(:exec)
      expect(mock_redis).to receive(:expire)

      result = Flapjack::Data::Event.next('events', :block => true,
        :archive_events => true, :redis => mock_redis)
      expect(result).to be_nil
    end

    it "rejects invalid event JSON (not archiving)" do
      bad_event_json = '{{{'
      expect(mock_redis).to receive(:brpop).with('events', 0).
        and_return(['events', bad_event_json])
      expect(mock_redis).to receive(:lpush).with(/^events_rejected:/, bad_event_json)

      result = Flapjack::Data::Event.next('events', :block => true,
        :archive_events => false, :redis => mock_redis)
      expect(result).to be_nil
    end

    ['type', 'state', 'entity', 'check', 'summary'].each do |required_key|

      it "rejects an event with missing '#{required_key}' key (archiving)" do
        bad_event_data = event_data.clone
        bad_event_data.delete(required_key)
        bad_event_json = bad_event_data.to_json
        expect(mock_redis).to receive(:brpoplpush).
          with('events', /^events_archive:/, 0).and_return(bad_event_json)
        expect(mock_redis).to receive(:multi)
        expect(mock_redis).to receive(:lrem).with(/^events_archive:/, 1, bad_event_json)
        expect(mock_redis).to receive(:lpush).with(/^events_rejected:/, bad_event_json)
        expect(mock_redis).to receive(:exec)
        expect(mock_redis).to receive(:expire)

        result = Flapjack::Data::Event.next('events', :block => true,
          :archive_events => true, :redis => mock_redis)
        expect(result).to be_nil
      end

      it "rejects an event with missing '#{required_key}' key (not archiving)" do
        bad_event_data = event_data.clone
        bad_event_data.delete(required_key)
        bad_event_json = bad_event_data.to_json
        expect(mock_redis).to receive(:brpop).with('events', 0).
          and_return(['events', bad_event_json])
        expect(mock_redis).to receive(:lpush).with(/^events_rejected:/, bad_event_json)

        result = Flapjack::Data::Event.next('events', :block => true,
          :archive_events => false, :redis => mock_redis)
        expect(result).to be_nil
      end

      it "rejects an event with invalid '#{required_key}' key (archiving)" do
        bad_event_data = event_data.clone
        bad_event_data[required_key] = {'hello' => 'there'}
        bad_event_json = bad_event_data.to_json
        expect(mock_redis).to receive(:brpoplpush).
          with('events', /^events_archive:/, 0).and_return(bad_event_json)
        expect(mock_redis).to receive(:multi)
        expect(mock_redis).to receive(:lrem).with(/^events_archive:/, 1, bad_event_json)
        expect(mock_redis).to receive(:lpush).with(/^events_rejected:/, bad_event_json)
        expect(mock_redis).to receive(:exec)
        expect(mock_redis).to receive(:expire)

        result = Flapjack::Data::Event.next('events', :block => true,
          :archive_events => true, :redis => mock_redis)
        expect(result).to be_nil
      end

      it "rejects an event with invalid '#{required_key}' key (not archiving)" do
        bad_event_data = event_data.clone
        bad_event_data[required_key] = {'hello' => 'there'}
        bad_event_json = bad_event_data.to_json
        expect(mock_redis).to receive(:brpop).with('events', 0).
          and_return(['events', bad_event_json])
        expect(mock_redis).to receive(:lpush).with(/^events_rejected:/, bad_event_json)

        result = Flapjack::Data::Event.next('events', :block => true,
          :archive_events => false, :redis => mock_redis)
        expect(result).to be_nil
      end
    end

    ['time', 'details', 'perfdata', 'acknowledgement_id', 'duration', 'tags'].each do |optional_key|
      it "rejects an event with invalid '#{optional_key}' key (archiving)" do
        bad_event_data = event_data.clone
        bad_event_data[optional_key] = {'hello' => 'there'}
        bad_event_json = bad_event_data.to_json
        expect(mock_redis).to receive(:brpoplpush).
          with('events', /^events_archive:/, 0).and_return(bad_event_json)
        expect(mock_redis).to receive(:multi)
        expect(mock_redis).to receive(:lrem).with(/^events_archive:/, 1, bad_event_json)
        expect(mock_redis).to receive(:lpush).with(/^events_rejected:/, bad_event_json)
        expect(mock_redis).to receive(:exec)
        expect(mock_redis).to receive(:expire)

        result = Flapjack::Data::Event.next('events', :block => true,
          :archive_events => true, :redis => mock_redis)
        expect(result).to be_nil
      end

      it "rejects an event with invalid '#{optional_key}' key (not archiving)" do
        bad_event_data = event_data.clone
        bad_event_data[optional_key] = {'hello' => 'there'}
        bad_event_json = bad_event_data.to_json
        expect(mock_redis).to receive(:brpop).with('events', 0).
          and_return(['events', bad_event_json])
        expect(mock_redis).to receive(:lpush).with(/^events_rejected:/, bad_event_json)

        result = Flapjack::Data::Event.next('events', :block => true,
          :archive_events => false, :redis => mock_redis)
        expect(result).to be_nil
      end
    end

    ['type', 'state'].each do |key|

      it "it matches case-insensitively for #{key} (archiving)" do
        case_event_data = event_data.clone
        case_event_data[key] = event_data[key].upcase
        expect(mock_redis).to receive(:brpoplpush).
          with('events', /^events_archive:/, 0).and_return(case_event_data.to_json)
        expect(mock_redis).to receive(:expire)

        result = Flapjack::Data::Event.next('events', :block => true,
          :archive_events => true, :redis => mock_redis)
        expect(result).to be_an_instance_of(Flapjack::Data::Event)
      end

      it "it matches case-insensitively for #{key} (not archiving)" do
        case_event_data = event_data.clone
        case_event_data[key] = event_data[key].upcase
        expect(mock_redis).to receive(:brpop).with('events', 0).
          and_return(['events', case_event_data.to_json])

        result = Flapjack::Data::Event.next('events',:block => true,
          :archive_events => false, :redis => mock_redis)
        expect(result).to be_an_instance_of(Flapjack::Data::Event)
      end
    end

    ['time', 'duration'].each do |key|

      it "it accepts an event with a numeric #{key} key (archiving)" do
        num_event_data = event_data.clone
        num_event_data[key] = event_data[key].to_i.to_s
        expect(mock_redis).to receive(:brpoplpush).
          with('events', /^events_archive:/, 0).and_return(num_event_data.to_json)
        expect(mock_redis).to receive(:expire)

        result = Flapjack::Data::Event.next('events', :block => true,
          :archive_events => true, :redis => mock_redis)
        expect(result).to be_an_instance_of(Flapjack::Data::Event)
      end

      it "it accepts an event with a numeric #{key} key (not archiving)" do
        num_event_data = event_data.clone
        num_event_data[key] = event_data[key].to_i.to_s
        expect(mock_redis).to receive(:brpop).with('events', 0).
          and_return(['events', num_event_data.to_json])

        result = Flapjack::Data::Event.next('events',:block => true,
          :archive_events => false, :redis => mock_redis)
        expect(result).to be_an_instance_of(Flapjack::Data::Event)
      end

      it "rejects an event with a non-numeric string #{key} key (archiving)" do
        bad_event_data = event_data.clone
        bad_event_data[key] = 'NaN'
        bad_event_json = bad_event_data.to_json
        expect(mock_redis).to receive(:brpoplpush).
          with('events', /^events_archive:/, 0).and_return(bad_event_json)
        expect(mock_redis).to receive(:multi)
        expect(mock_redis).to receive(:lrem).with(/^events_archive:/, 1, bad_event_json)
        expect(mock_redis).to receive(:lpush).with(/^events_rejected:/, bad_event_json)
        expect(mock_redis).to receive(:exec)
        expect(mock_redis).to receive(:expire)

        result = Flapjack::Data::Event.next('events', :block => true,
          :archive_events => true, :redis => mock_redis)
        expect(result).to be_nil
      end

      it "rejects an event with a non-numeric string #{key} key (not archiving)" do
        bad_event_data = event_data.clone
        bad_event_data[key] = 'NaN'
        bad_event_json = bad_event_data.to_json
        expect(mock_redis).to receive(:brpop).with('events', 0).
          and_return(['events', bad_event_json])
        expect(mock_redis).to receive(:lpush).with(/^events_rejected:/, bad_event_json)

        result = Flapjack::Data::Event.next('events', :block => true,
          :archive_events => false, :redis => mock_redis)
        expect(result).to be_nil
      end

    end

    it "returns a count of pending events" do
      events_len = 23
      expect(mock_redis).to receive(:llen).with('events').and_return(events_len)

      pc = Flapjack::Data::Event.pending_count('events', :redis => mock_redis)
      expect(pc).to eq(events_len)
    end

    it "creates a notification testing event" do
      expect(Time).to receive(:now).and_return(time)
      expect(mock_redis).to receive(:lpush).with('events', /"testing"/ )

      Flapjack::Data::Event.test_notifications(entity_name, check,
        :summary => 'test', :details => 'testing', :redis => mock_redis)
    end

    it "creates an acknowledgement event" do
      expect(Time).to receive(:now).and_return(time)
      expect(mock_redis).to receive(:lpush).with('events', /"acking"/ )

      Flapjack::Data::Event.create_acknowledgement(entity_name, check,
        :summary => 'acking', :time => time.to_i, :redis => mock_redis)
    end

  end

  context 'instance' do
    let(:event) { Flapjack::Data::Event.new(event_data) }

    it "matches the data it is initialised with" do
      expect(event.entity).to eq(event_data['entity'])
      expect(event.state).to eq(event_data['state'])
      expect(event.duration).to eq(event_data['duration'])
      expect(event.time).to eq(event_data['time'])
      expect(event.id).to eq('xyz-example.com:ping')
      expect(event.type).to eq('service')
      expect(event.tags).to be_an_instance_of(Set)
      expect(event.tags).to include('dev')
      expect(event.tags).to_not include('prod')

      expect(event).to be_a_service
      expect(event).to be_a_service
      expect(event).not_to be_an_acknowledgement
      expect(event).not_to be_a_test_notifications
      expect(event).not_to be_ok
      expect(event).to be_a_failure
    end

  end

end
