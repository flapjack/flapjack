require 'spec_helper'
require 'flapjack/data/event'

describe Flapjack::Data::Event do

  let(:entity_name) { 'xyz-example.com' }
  let(:check)       { 'ping' }
  let(:redis)  { double(Redis) }

  let!(:time) { Time.now}

  let(:event_data) { {'type'    => 'service',
                      'state'   => 'critical',
                      'entity'  => entity_name,
                      'check'   => check,
                      'time'    => time.to_i,
                      'summary' => "timeout",
                      'details' => "couldn't access",
                      'acknowledgement_id' => '1234',
                      'duration' => (60 * 60) }
  }

  context 'class' do

    before(:each) do
      allow(Flapjack).to receive(:redis).and_return(redis)
    end

    it "returns the next event (archiving)" do
      expect(redis).to receive(:rpoplpush).with('events', /^events_archive:/).and_return(event_data.to_json, nil)
      expect(redis).to receive(:expire)

      Flapjack::Data::Event.foreach_on_queue('events', :archive_events => true) {|result|
        expect(result).to be_an_instance_of(Flapjack::Data::Event)
      }
    end

    it "returns the next event (not archiving)" do
      expect(redis).to receive(:rpop).with('events').and_return(event_data.to_json, nil)

      Flapjack::Data::Event.foreach_on_queue('events', :archive_events => false) {|result|
        expect(result).to be_an_instance_of(Flapjack::Data::Event)
      }
    end

    it "rejects invalid event JSON (archiving)" do
      bad_event_json = '{{{'
      expect(redis).to receive(:rpoplpush).
        with('events', /^events_archive:/).and_return(bad_event_json, nil)
      expect(redis).to receive(:multi)
      expect(redis).to receive(:lrem).with(/^events_archive:/, 1, bad_event_json)
      expect(redis).to receive(:lpush).with(/^events_rejected:/, bad_event_json)
      expect(redis).to receive(:exec)
      expect(redis).to receive(:expire)

      Flapjack::Data::Event.foreach_on_queue('events', :archive_events => true) {|result|
        expect(result).to be_nil
      }
    end

    it "rejects invalid event JSON (not archiving)" do
      bad_event_json = '{{{'
      expect(redis).to receive(:rpop).with('events').
        and_return(bad_event_json, nil)
      expect(redis).to receive(:lpush).with(/^events_rejected:/, bad_event_json)

      Flapjack::Data::Event.foreach_on_queue('events', :archive_events => false) {|result|
        expect(result).to be_nil
      }
    end

    ['type', 'state', 'entity', 'check', 'summary'].each do |required_key|

      it "rejects an event with missing '#{required_key}' key (archiving)" do
        bad_event_data = event_data.clone
        bad_event_data.delete(required_key)
        bad_event_json = bad_event_data.to_json
        expect(redis).to receive(:rpoplpush).
          with('events', /^events_archive:/).and_return(bad_event_json, nil)
        expect(redis).to receive(:multi)
        expect(redis).to receive(:lrem).with(/^events_archive:/, 1, bad_event_json)
        expect(redis).to receive(:lpush).with(/^events_rejected:/, bad_event_json)
        expect(redis).to receive(:exec)
        expect(redis).to receive(:expire)

        Flapjack::Data::Event.foreach_on_queue('events', :archive_events => true) {|result|
          expect(result).to be_nil
        }
      end

      it "rejects an event with missing '#{required_key}' key (not archiving)" do
        bad_event_data = event_data.clone
        bad_event_data.delete(required_key)
        bad_event_json = bad_event_data.to_json
        expect(redis).to receive(:rpop).with('events').
          and_return(bad_event_json, nil)
        expect(redis).to receive(:lpush).with(/^events_rejected:/, bad_event_json)

        Flapjack::Data::Event.foreach_on_queue('events', :archive_events => false) {|result|
          expect(result).to be_nil
        }
      end

      it "rejects an event with invalid '#{required_key}' key (archiving)" do
        bad_event_data = event_data.clone
        bad_event_data[required_key] = {'hello' => 'there'}
        bad_event_json = bad_event_data.to_json
        expect(redis).to receive(:rpoplpush).
          with('events', /^events_archive:/).and_return(bad_event_json, nil)
        expect(redis).to receive(:multi)
        expect(redis).to receive(:lrem).with(/^events_archive:/, 1, bad_event_json)
        expect(redis).to receive(:lpush).with(/^events_rejected:/, bad_event_json)
        expect(redis).to receive(:exec)
        expect(redis).to receive(:expire)

        Flapjack::Data::Event.foreach_on_queue('events', :archive_events => true) {|result|
          expect(result).to be_nil
        }
      end

      it "rejects an event with invalid '#{required_key}' key (not archiving)" do
        bad_event_data = event_data.clone
        bad_event_data[required_key] = {'hello' => 'there'}
        bad_event_json = bad_event_data.to_json
        expect(redis).to receive(:rpop).with('events').
          and_return(bad_event_json, nil)
        expect(redis).to receive(:lpush).with(/^events_rejected:/, bad_event_json)

        Flapjack::Data::Event.foreach_on_queue('events', :archive_events => false) {|result|
          expect(result).to be_nil
        }
      end
    end

    ['time', 'details', 'acknowledgement_id', 'duration'].each do |optional_key|
      it "rejects an event with invalid '#{optional_key}' key (archiving)" do
        bad_event_data = event_data.clone
        bad_event_data[optional_key] = {'hello' => 'there'}
        bad_event_json = bad_event_data.to_json
        expect(redis).to receive(:rpoplpush).
          with('events', /^events_archive:/).and_return(bad_event_json, nil)
        expect(redis).to receive(:multi)
        expect(redis).to receive(:lrem).with(/^events_archive:/, 1, bad_event_json)
        expect(redis).to receive(:lpush).with(/^events_rejected:/, bad_event_json)
        expect(redis).to receive(:exec)
        expect(redis).to receive(:expire)

        Flapjack::Data::Event.foreach_on_queue('events', :archive_events => true) {|result|
          expect(result).to be_nil
        }
      end

      it "rejects an event with invalid '#{optional_key}' key (not archiving)" do
        bad_event_data = event_data.clone
        bad_event_data[optional_key] = {'hello' => 'there'}
        bad_event_json = bad_event_data.to_json
        expect(redis).to receive(:rpop).with('events').
          and_return(bad_event_json, nil)
        expect(redis).to receive(:lpush).with(/^events_rejected:/, bad_event_json)

        Flapjack::Data::Event.foreach_on_queue('events', :archive_events => false) {|result|
          expect(result).to be_nil
        }
      end
    end

    ['time', 'duration'].each do |key|

      it "rejects an event with a non-numeric or numeric string #{key} key (not archiving)" do
        bad_event_data = event_data.clone
        bad_event_data[key] = 'NaN'
        bad_event_json = bad_event_data.to_json
        expect(redis).to receive(:rpop).with('events').
          and_return(bad_event_json, nil)
        expect(redis).to receive(:lpush).with(/^events_rejected:/, bad_event_json)

        Flapjack::Data::Event.foreach_on_queue('events', :archive_events => false) {|result|
          expect(result).to be_nil
        }
      end

      it "rejects an event with a non-numeric or numeric string #{key} key (not archiving)" do
        bad_event_data = event_data.clone
        bad_event_data[key] = 'NaN'
        bad_event_json = bad_event_data.to_json
        expect(redis).to receive(:rpop).with('events').
          and_return(bad_event_json, nil)
        expect(redis).to receive(:lpush).with(/^events_rejected:/, bad_event_json)

        Flapjack::Data::Event.foreach_on_queue('events', :archive_events => false) {|result|
          expect(result).to be_nil
        }
      end

    end

    it "returns a count of pending events" do
      events_len = 23
      expect(redis).to receive(:llen).with('events').and_return(events_len)

      pc = Flapjack::Data::Event.pending_count('events')
      expect(pc).to eq(events_len)
    end

    it "creates a notification testing event" do
      expect(Time).to receive(:now).and_return(time)
      expect(redis).to receive(:multi).and_yield
      expect(redis).to receive(:lpush).with('events', /"testing"/ )
      expect(redis).to receive(:lpush).with('events_actions', anything)

      Flapjack::Data::Event.test_notifications('events', entity_name, check,
        :summary => 'test', :details => 'testing')
    end

    it "creates an acknowledgement event" do
      expect(Time).to receive(:now).and_return(time)
      expect(redis).to receive(:multi).and_yield
      expect(redis).to receive(:lpush).with('events', /"acking"/ )
      expect(redis).to receive(:lpush).with('events_actions', anything)

      Flapjack::Data::Event.create_acknowledgement('events', entity_name, check,
        :summary => 'acking', :time => time.to_i)
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

      expect(event).to be_a_service
      expect(event).to be_a_service
      expect(event).not_to be_an_acknowledgement
      expect(event).not_to be_a_test_notifications
      expect(event).not_to be_ok
      expect(event).to be_a_failure
    end
  end

end
