require 'spec_helper'
require 'flapjack/data/event'

describe Flapjack::Data::Event do

  let(:entity_name) { 'xyz-example.com' }
  let(:check)       { 'ping' }
  let(:mock_redis)  { double(::Redis) }

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

    it "returns the next event (blocking, archiving)" do
      expect(mock_redis).to receive(:brpoplpush).with('events', /^events_archive:/, 0).and_return(event_data.to_json)
      expect(mock_redis).to receive(:expire)

      result = Flapjack::Data::Event.next('events', :block => true, :archive_events => true, :redis => mock_redis)
      expect(result).to be_an_instance_of(Flapjack::Data::Event)
    end

    it "returns the next event (blocking, not archiving)" do
      expect(mock_redis).to receive(:brpop).with('events', 0).and_return(['events', event_data.to_json])

      result = Flapjack::Data::Event.next('events', :block => true, :archive_events => false, :redis => mock_redis)
      expect(result).to be_an_instance_of(Flapjack::Data::Event)
    end

    it "returns the next event (non-blocking, archiving)" do
      expect(mock_redis).to receive(:rpoplpush).with('events', /^events_archive:/).and_return(event_data.to_json)
      expect(mock_redis).to receive(:expire)

      result = Flapjack::Data::Event.next('events', :block => false, :archive_events => true, :redis => mock_redis)
      expect(result).to be_an_instance_of(Flapjack::Data::Event)
    end

    it "returns the next event (non-blocking, not archiving)" do
      expect(mock_redis).to receive(:rpop).with('events').and_return(event_data.to_json)

      result = Flapjack::Data::Event.next('events', :block => false, :archive_events => false, :redis => mock_redis)
      expect(result).to be_an_instance_of(Flapjack::Data::Event)
    end

    it "handles invalid event JSON"

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

      expect(event).to be_a_service
      expect(event).to be_a_service
      expect(event).not_to be_an_acknowledgement
      expect(event).not_to be_a_test_notifications
      expect(event).not_to be_ok
      expect(event).to be_a_failure
    end

  end

end
