require 'spec_helper'
require 'flapjack/gateways/email'

describe Flapjack::Gateways::Email, :logger => true do

  it "sends a mail with text and html parts" do
    redis = double(Redis)
    Flapjack.stub(:redis).and_return(redis)

    message = {'notification_type'   => 'recovery',
               'contact_first_name'  => 'John',
               'contact_last_name'   => 'Smith',
               'state'               => 'ok',
               'state_duration'      => 2,
               'summary'             => 'smile',
               'last_state'          => 'problem',
               'last_summary'        => 'frown',
               'time'                => Time.now.to_i,
               'address'             => 'johnsmith@example.com',
               'entity'              => 'example.com',
               'check'               => 'ping'}

    redis.should_receive(:rpop).with('email_notifications').and_return(message.to_json, nil)
    redis.should_receive(:quit)
    redis.should_receive(:brpop).with('email_notifications_actions').and_raise(Flapjack::PikeletStop)

    Mail::TestMailer.deliveries.should be_empty

    lock = double(Monitor)
    lock.should_receive(:synchronize).and_yield

    email_gw = Flapjack::Gateways::Email.new(:lock => lock, :config => {}, :logger => @logger)
    expect { email_gw.start }.to raise_error(Flapjack::PikeletStop)

    Mail::TestMailer.deliveries.should have(1).mail
  end

end
