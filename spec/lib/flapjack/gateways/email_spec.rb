require 'spec_helper'
require 'flapjack/gateways/email'

describe Flapjack::Gateways::Email, :logger => true do

  it "sends a mail with text and html parts" do
    redis = double(Redis)
    allow(Flapjack).to receive(:redis).and_return(redis)

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
               'event_id'            => 'example.com:ping'}

    expect(Flapjack::Data::Message).to receive(:foreach_on_queue).
      with('email_notifications', :logger => @logger).
      and_yield(message)
    expect(Flapjack::Data::Message).to receive(:wait_for_queue).
      with('email_notifications').
      and_raise(Flapjack::PikeletStop)

    expect(Mail::TestMailer.deliveries).to be_empty

    lock = double(Monitor)
    expect(lock).to receive(:synchronize).and_yield

    email_gw = Flapjack::Gateways::Email.new(:lock => lock, :config => {}, :logger => @logger)
    expect { email_gw.start }.to raise_error(Flapjack::PikeletStop)

    expect(Mail::TestMailer.deliveries.size).to eq(1)
  end

end
