require 'spec_helper'
require 'flapjack/gateways/email'

describe Flapjack::Gateways::Email, :logger => true do

  it "sends a mail with text and html parts" do
    email = double('email')

    entity_check = double(Flapjack::Data::EntityCheck)
    redis = double('redis')

    # TODO better checking of what gets passed here
    EM::P::SmtpClient.should_receive(:send).with(
      hash_including(:host    => 'localhost',
                     :port    => 25)).and_return(email)

    response = double(response)
    response.should_receive(:"respond_to?").with(:code).and_return(true)
    response.should_receive(:code).and_return(250)

    EM::Synchrony.should_receive(:sync).with(email).and_return(response)

    notification = {'notification_type'   => 'recovery',
                    'contact_first_name'  => 'John',
                    'contact_last_name'   => 'Smith',
                    'state'               => 'ok',
                    'state_duration'      => 2,
                    'summary'             => 'smile',
                    'last_state'          => 'problem',
                    'last_summary'        => 'frown',
                    'time'                => Time.now.to_i,
                    'event_id'            => 'example.com:ping'}

    Flapjack::Gateways::Email.instance_variable_set('@config', {})
    Flapjack::Gateways::Email.instance_variable_set('@redis', redis)
    Flapjack::Gateways::Email.instance_variable_set('@logger', @logger)
    Flapjack::Gateways::Email.start
    Flapjack::Gateways::Email.perform(notification)
  end

end
