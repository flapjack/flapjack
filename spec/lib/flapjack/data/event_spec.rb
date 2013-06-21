require 'spec_helper'
require 'flapjack/data/event'

describe Flapjack::Data::Event, :redis => true do

  let(:entity_name) { 'example.org' }
  let(:check)       { 'ping' }

  let!(:time) { Time.now}

  it "creates a notification testing event" do
    Time.should_receive(:now).and_return(time)
    @redis.should_receive(:rpush).with('events', /"testing"/ )

    Flapjack::Data::Event.test_notifications(entity_name, check,
      :summary => 'test', :details => 'testing', :redis => @redis)
  end

  it "creates an acknowledgement event" do
    Time.should_receive(:now).and_return(time)
    @redis.should_receive(:rpush).with('events', /"acking"/ )

    Flapjack::Data::Event.create_acknowledgement(entity_name, check,
      :summary => 'acking', :time => time.to_i, :redis => @redis)
  end

end