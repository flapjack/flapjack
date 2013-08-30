require 'spec_helper'
require 'flapjack/data/event'

describe Flapjack::Data::Event do

  let(:entity_name) { 'xyz-example.com' }
  let(:check)       { 'ping' }
  let(:redis)  { mock(Redis) }

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
      Flapjack.stub(:redis).and_return(redis)
    end

    it "returns the next event (non-blocking, archiving)" do
      redis.should_receive(:rpoplpush).with('events', /^events_archive:/).and_return(event_data.to_json, nil)
      redis.should_receive(:expire)

      Flapjack::Data::Event.foreach_on_queue('events', :archive_events => true) {|result|
        result.should be_an_instance_of(Flapjack::Data::Event)
      }
    end

    it "returns the next event (non-blocking, not archiving)" do
      redis.should_receive(:rpop).with('events').and_return(event_data.to_json, nil)

      Flapjack::Data::Event.foreach_on_queue('events', :archive_events => false) {|result|
        result.should be_an_instance_of(Flapjack::Data::Event)
      }
    end

    it "blocks waiting for an event wakeup"

    it "handles invalid event JSON"

    it "returns a count of pending events" do
      events_len = 23
      redis.should_receive(:llen).with('events').and_return(events_len)

      pc = Flapjack::Data::Event.pending_count('events')
      pc.should == events_len
    end

    it "creates a notification testing event" do
      Time.should_receive(:now).and_return(time)
      redis.should_receive(:multi).and_yield
      redis.should_receive(:lpush).with('events', /"testing"/ )
      redis.should_receive(:lpush).with('events_actions', anything)

      Flapjack::Data::Event.test_notifications('events', entity_name, check,
        :summary => 'test', :details => 'testing')
    end

    it "creates an acknowledgement event" do
      Time.should_receive(:now).and_return(time)
      redis.should_receive(:multi).and_yield
      redis.should_receive(:lpush).with('events', /"acking"/ )
      redis.should_receive(:lpush).with('events_actions', anything)

      Flapjack::Data::Event.create_acknowledgement('events', entity_name, check,
        :summary => 'acking', :time => time.to_i)
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
    it { should_not be_an_acknowledgement }
    it { should_not be_a_test_notifications }
    it { should_not be_ok }
    it { should be_a_failure }
  end

end
