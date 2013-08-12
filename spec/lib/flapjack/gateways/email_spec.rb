require 'spec_helper'
require 'flapjack/gateways/email'

describe Flapjack::Gateways::Email, :logger => true do

  it "sends a mail with text and html parts" do
    entity_check = mock(Flapjack::Data::EntityCheck)
    entity_check.should_receive(:in_scheduled_maintenance?).and_return(false)
    entity_check.should_receive(:in_unscheduled_maintenance?).and_return(false)
    entity_check.should_receive(:last_change).and_return(Time.now.to_i)

    redis = mock('redis')
    ::Redis.should_receive(:new).and_return(redis)

    Flapjack::Data::EntityCheck.should_receive(:for_event_id).
      with('example.com:ping', :redis => redis).and_return(entity_check)

    message = {'notification_type'   => 'recovery',
               'contact_first_name'  => 'John',
               'contact_last_name'   => 'Smith',
               'state'               => 'ok',
               'summary'             => 'smile',
               'last_state'          => 'problem',
               'last_summary'        => 'frown',
               'time'                => Time.now.to_i,
               'address'             => 'johnsmith@example.com',
               'event_id'            => 'example.com:ping'}

    Flapjack::Data::Message.should_receive(:foreach_on_queue).
      with('email_notifications', :redis => redis, :logger => @logger).
      and_yield(message)
    Flapjack::Data::Message.should_receive(:wait_for_queue).
      with('email_notifications', :redis => redis).
      and_raise(Flapjack::PikeletStop)

    Mail::TestMailer.deliveries.should be_empty

    email_gw = Flapjack::Gateways::Email.new(:config => {}, :logger => @logger)
    expect { email_gw.start }.to raise_error(Flapjack::PikeletStop)

    Mail::TestMailer.deliveries.should have(1).mail
  end

end
