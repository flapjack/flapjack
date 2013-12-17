require 'spec_helper'
require 'flapjack/notifier'

describe Flapjack::Notifier, :logger => true do

  let(:redis) { double(::Redis) }

  let(:queue) { double(Flapjack::RecordQueue) }

  it "starts up, runs and shuts down" do
    config = {'default_contact_timezone' => 'Australia/Broken_Hill'.taint}

    expect(Flapjack::RecordQueue).to receive(:new).with('notifications',
      Flapjack::Data::Notification).and_return(queue)

    ['email', 'sms', 'pagerduty', 'jabber'].each do |media_type|
      expect(Flapjack::RecordQueue).to receive(:new).with("#{media_type}_notifications",
        Flapjack::Data::Alert)
    end

    lock = double(Monitor)
    expect(lock).to receive(:synchronize).and_yield
    expect(queue).to receive(:foreach) # assume no messages for now
    expect(queue).to receive(:wait).and_raise(Flapjack::PikeletStop)

    notifier = Flapjack::Notifier.new(:lock => lock, :config => config, :logger => @logger)

    # redis.should_receive(:rpop).with('notifications').and_return("}", nil)
    expect(redis).to receive(:quit)
    # redis.should_receive(:brpop).with('notifications_actions').and_raise(Flapjack::PikeletStop)
    allow(Flapjack).to receive(:redis).and_return(redis)

    expect { notifier.start }.to raise_error(Flapjack::PikeletStop)
  end

end
