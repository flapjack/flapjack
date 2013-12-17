require 'spec_helper'
require 'flapjack/data/event'

describe Flapjack::Data::Event do

  let(:entity_name) { 'xyz-example.com' }
  let(:check_name)  { 'ping' }
  let(:redis)  { double(Redis) }

  let!(:time) { Time.now}

  let(:event_data) { {'type'    => 'service',
                      'state'   => 'critical',
                      'entity'  => entity_name,
                      'check'   => check_name,
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

    it "blocks waiting for an event wakeup"

    it "handles invalid event JSON"

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

      Flapjack::Data::Event.test_notifications('events', entity_name, check_name,
        :summary => 'test', :details => 'testing')
    end

    it "creates an acknowledgement event" do
      expect(Time).to receive(:now).and_return(time)
      expect(redis).to receive(:multi).and_yield
      expect(redis).to receive(:lpush).with('events', /"acking"/ )
      expect(redis).to receive(:lpush).with('events_actions', anything)

      Flapjack::Data::Event.create_acknowledgement('events', entity_name, check_name,
        :summary => 'acking', :time => time.to_i)
    end

  end

  context 'instance' do
    let(:event) { Flapjack::Data::Event.new(event_data) }

    it "matches the data it is initialised with" do
      expect(event.entity_name).to eq(event_data['entity'])
      expect(event.state).to eq(event_data['state'])
      expect(event.duration).to eq(event_data['duration'])
      expect(event.time).to eq(event_data['time'])
      expect(event.id).to eq('xyz-example.com:ping')
      expect(event.type).to eq('service')

      expect(event).to be_a_service
      expect(event).to be_a_service
      expect(event).not_to be_an_acknowledgement
      expect(event).not_to be_a_test_notifications
    end
  end

end
