require 'spec_helper'
require 'flapjack/data/event'

describe Flapjack::Data::Event do

  let(:entity_name) { 'xyz-example.com' }
  let(:check_name)  { 'ping' }
  let(:redis)  { double(Redis) }

  let!(:time) { Time.now}

  let(:event_data) { {'state'    => 'critical',
                      'entity'   => entity_name,
                      'check'    => check_name,
                      'time'     => time.to_i,
                      'summary'  => 'timeout',
                      'details'  => "couldn't access",
                      'perfdata' => "/=5504MB;5554;6348;0;7935",
                      'acknowledgement_id' => '1234',
                      'duration' => (60 * 60) }
                   }

  context 'class' do

    let(:check) { double(Flapjack::Data::Check) }

    before(:each) do
      allow(Flapjack).to receive(:redis).and_return(redis)
    end

    it "returns a count of pending events" do
      events_len = 23
      expect(redis).to receive(:llen).with('events').and_return(events_len)

      pc = Flapjack::Data::Event.pending_count('events')
      expect(pc).to eq(events_len)
    end

    it "creates a notification testing event" do
      expect(check).to receive(:name).and_return(check_name)

      expect(Time).to receive(:now).and_return(time)
      expect(redis).to receive(:multi).and_yield
      expect(redis).to receive(:lpush).with('events', /"testing"/ )
      expect(redis).to receive(:lpush).with('events_actions', anything)

      Flapjack::Data::Event.test_notifications('events', [check],
        :summary => 'test', :details => 'testing')
    end

    it "creates an acknowledgement event" do
      expect(check).to receive(:name).and_return(check_name)

      expect(Time).to receive(:now).and_return(time)
      expect(redis).to receive(:multi).and_yield
      expect(redis).to receive(:lpush).with('events', /"acking"/ )
      expect(redis).to receive(:lpush).with('events_actions', anything)

      Flapjack::Data::Event.create_acknowledgements('events', [check],
        :summary => 'acking', :time => time.to_i)
    end

  end

  context 'instance' do
    let(:event) { Flapjack::Data::Event.new(event_data) }

    it "matches the data it is initialised with" do
      expect(event.state).to eq(event_data['state'])
      expect(event.duration).to eq(event_data['duration'])
      expect(event.time).to eq(event_data['time'])
      expect(event.id).to eq('xyz-example.com:ping')
    end
  end

  [:state, :check].each do |required_key|
    it "rejects an event with missing '#{required_key}' key" do
      bad_event_data = event_data.clone
      bad_event_data.delete(required_key.to_s)
      bad_event_json = Flapjack.dump_json(bad_event_data)

      _, errors = Flapjack::Data::Event.parse_and_validate(bad_event_json)
      expect(errors).not_to be_empty
    end

    it "rejects an event with invalid '#{required_key}' key" do
      bad_event_data = event_data.clone
      bad_event_data[required_key] = {'hello' => 'there'}
      bad_event_json = Flapjack.dump_json(bad_event_data)

      _, errors = Flapjack::Data::Event.parse_and_validate(bad_event_json)
      expect(errors).not_to be_empty
    end
  end

  [:entity, :time, :initial_failure_delay, :repeat_failure_delay, :summary,
   :details, :perfdata, :acknowledgement_id, :duration].each do |optional_key|

    it "rejects an event with invalid '#{optional_key}' key" do
      bad_event_data = event_data.clone
      bad_event_data[optional_key.to_s] = {'hello' => 'there'}
      bad_event_json = Flapjack.dump_json(bad_event_data)

      _, errors = Flapjack::Data::Event.parse_and_validate(bad_event_json)
      expect(errors).not_to be_empty
    end

  end

  [:time, :initial_failure_delay, :repeat_failure_delay, :duration].each do |key|
    it "accepts an event with a numeric string #{key} key" do
      numstr_event_data = event_data.clone
      numstr_event_data[key.to_s] = '352'
      numstr_event_json = Flapjack.dump_json(numstr_event_data)

      _, errors = Flapjack::Data::Event.parse_and_validate(numstr_event_json)
      expect(errors).to be_empty
    end

    it "rejects an event with a non-numeric or numeric string #{key} key" do
      bad_event_data = event_data.clone
      bad_event_data[key] = 'NaN'
      bad_event_json = Flapjack.dump_json(bad_event_data)

      _, errors = Flapjack::Data::Event.parse_and_validate(bad_event_json)
      expect(errors).not_to be_empty
    end

  end

end
