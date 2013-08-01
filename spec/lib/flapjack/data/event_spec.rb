require 'spec_helper'
require 'flapjack/data/event'

describe Flapjack::Data::Event do

  let(:entity_name) { 'xyz-example.com' }
  let(:check)       { 'ping' }
  let(:mock_redis)  { mock(::Redis) }

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
      mock_redis.should_receive(:brpoplpush).with('events', /^events_archive:/, 0).and_return(event_data.to_json)
      mock_redis.should_receive(:expire)

      result = Flapjack::Data::Event.next('events', :block => true, :archive_events => true, :redis => mock_redis)
      result.should be_an_instance_of(Flapjack::Data::Event)
    end

    it "returns the next event (blocking, not archiving)" do
      mock_redis.should_receive(:brpop).with('events', 0).and_return(['events', event_data.to_json])

      result = Flapjack::Data::Event.next('events', :block => true, :archive_events => false, :redis => mock_redis)
      result.should be_an_instance_of(Flapjack::Data::Event)
    end

    it "returns the next event (non-blocking, archiving)" do
      mock_redis.should_receive(:rpoplpush).with('events', /^events_archive:/).and_return(event_data.to_json)
      mock_redis.should_receive(:expire)

      result = Flapjack::Data::Event.next('events', :block => false, :archive_events => true, :redis => mock_redis)
      result.should be_an_instance_of(Flapjack::Data::Event)
    end

    it "returns the next event (non-blocking, not archiving)" do
      mock_redis.should_receive(:rpop).with('events').and_return(event_data.to_json)

      result = Flapjack::Data::Event.next('events', :block => false, :archive_events => false, :redis => mock_redis)
      result.should be_an_instance_of(Flapjack::Data::Event)
    end

    it "handles invalid event JSON"

    it "returns a count of pending events" do
      events_len = 23
      mock_redis.should_receive(:llen).with('events').and_return(events_len)

      pc = Flapjack::Data::Event.pending_count('events', :redis => mock_redis)
      pc.should == events_len
    end

    it "creates a notification testing event" do
      Time.should_receive(:now).and_return(time)
      mock_redis.should_receive(:lpush).with('events', /"testing"/ )

      Flapjack::Data::Event.test_notifications(entity_name, check,
        :summary => 'test', :details => 'testing', :redis => mock_redis)
    end

    it "creates an acknowledgement event" do
      Time.should_receive(:now).and_return(time)
      mock_redis.should_receive(:lpush).with('events', /"acking"/ )

      Flapjack::Data::Event.create_acknowledgement(entity_name, check,
        :summary => 'acking', :time => time.to_i, :redis => mock_redis)
    end

  end

  context 'instance' do
    subject { Flapjack::Data::Event.new(event_data) }

    its(:entity)   { should == event_data['entity'] }
    its(:state)    { should == event_data['state'] }
    its(:duration) { should == event_data['duration'] }
    its(:time)     { should == event_data['time'] }
    its(:id)       { should == 'xyz-example.com:ping' }
    its(:client)   { should == 'xyz' }
    its(:type)     { should == 'service' }

    it { should be_a_service }
    it { should_not be_a_acknowledgement }
    it { should_not be_a_test_notifications }
    it { should_not be_ok }
    it { should be_a_failure }
  end

end
