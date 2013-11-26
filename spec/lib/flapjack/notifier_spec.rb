require 'spec_helper'
require 'flapjack/notifier'

describe Flapjack::Notifier, :logger => true do

  let(:redis) { double(::Redis) }

  let(:queue) { double(Flapjack::RecordQueue) }

  it "starts up, runs and shuts down" do
    config = {'default_contact_timezone' => 'Australia/Broken_Hill'.taint}

    Flapjack::RecordQueue.should_receive(:new).with('notifications',
      Flapjack::Data::Notification).and_return(queue)

    ['email', 'sms', 'pagerduty', 'jabber'].each do |media_type|
      Flapjack::RecordQueue.should_receive(:new).with("#{media_type}_notifications",
        Flapjack::Data::Alert)
    end

    lock = double(Monitor)
    lock.should_receive(:synchronize).and_yield
    queue.should_receive(:foreach) # assume no messages for now
    queue.should_receive(:wait).and_raise(Flapjack::PikeletStop)

    notifier = Flapjack::Notifier.new(:lock => lock, :config => config, :logger => @logger)

    # redis.should_receive(:rpop).with('notifications').and_return("}", nil)
    redis.should_receive(:quit)
    # redis.should_receive(:brpop).with('notifications_actions').and_raise(Flapjack::PikeletStop)
    Flapjack.stub(:redis).and_return(redis)

    expect { notifier.start }.to raise_error(Flapjack::PikeletStop)
  end

end
