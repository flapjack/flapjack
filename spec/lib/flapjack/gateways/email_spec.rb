require 'spec_helper'
require 'flapjack/gateways/email'

describe Flapjack::Gateways::Email, :logger => true do

  before(:each) do
    Flapjack::Gateways::Email.instance_variable_set('@config', {})
    Flapjack::Gateways::Email.instance_variable_set('@logger', @logger)
    Flapjack::Gateways::Email.start
  end

  it "sends a mail with text and html parts" do
    email = mock('email')

    entity_check = mock(Flapjack::Data::EntityCheck)
    entity_check.should_receive(:in_scheduled_maintenance?).and_return(false)
    entity_check.should_receive(:in_unscheduled_maintenance?).and_return(false)

    redis = mock('redis')
    ::Resque.should_receive(:redis).and_return(redis)

    Flapjack::Data::EntityCheck.should_receive(:for_event_id).
      with('example.com:ping', :redis => redis).and_return(entity_check)

    # TODO better checking of what gets passed here
    EM::P::SmtpClient.should_receive(:send).with(
      hash_including(:host    => 'localhost',
                     :port    => 25)).and_return(email)

    response = mock(response)
    response.should_receive(:"respond_to?").with(:code).and_return(true)
    response.should_receive(:code).and_return(250)

    EM::Synchrony.should_receive(:sync).with(email).and_return(response)

    notification = {'notification_type'   => 'recovery',
                    'contact_first_name'  => 'John',
                    'contact_last_name'   => 'Smith',
                    'state'               => 'ok',
                    'summary'             => 'smile',
                    'last_state'          => 'problem',
                    'last_summary'        => 'frown',
                    'time'                => Time.now.to_i,
                    'event_id'            => 'example.com:ping'}

    Flapjack::Gateways::Email.perform(notification)
  end

end