require 'spec_helper'
require 'flapjack/notifier'

describe Flapjack::Notifier, :logger => true do

  let(:redis) { double(::Redis) }

  let(:queue) { double(Flapjack::RecordQueue) }

  it "starts up, runs and shuts down" do
    config = {'default_contact_timezone' => 'Australia/Broken_Hill'.taint,
              'email_queue'     => 'email_notifications',
              'sms_queue'       => 'sms_notifications',
              'pagerduty_queue' => 'pagerduty_notifications',
              'jabber_queue'    => 'jabber_notifications'}

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

    expect(redis).to receive(:quit)
    allow(Flapjack).to receive(:redis).and_return(redis)

    expect { notifier.start }.to raise_error(Flapjack::PikeletStop)
  end

end
