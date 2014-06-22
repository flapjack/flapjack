require 'spec_helper'
require 'flapjack/gateways/email'

describe Flapjack::Gateways::Email, :logger => true do

  it "can have a custom from email address" do
    email = double('email')
    redis = double('redis')

    expect(EM::P::SmtpClient).to receive(:send).with(
      hash_including(host: 'localhost',
                     port: 25,
                     from: "from@example.org")
    ).and_return(email)

    response = double(response)
    expect(response).to receive(:"respond_to?").with(:code).and_return(true)
    expect(response).to receive(:code).and_return(250)

    expect(EM::Synchrony).to receive(:sync).with(email).and_return(response)

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

    config = {"smtp_config" => {'from' => 'from@example.org'}}
    Flapjack::Gateways::Email.instance_variable_set('@config', config)
    Flapjack::Gateways::Email.instance_variable_set('@redis', redis)
    Flapjack::Gateways::Email.instance_variable_set('@logger', @logger)
    Flapjack::Gateways::Email.start
    Flapjack::Gateways::Email.perform(notification)
  end

  it "can have a custom reply-to address" do
    email = double('email')
    redis = double('redis')

    expect(EM::P::SmtpClient).to receive(:send) { |message|  
      # NOTE No access to headers directly. Must be determined from message content  
      expect( message[:content] ).to include("Reply-To: reply-to@example.com")
      # NOTE Ensure we haven't trashed any other arguments
      expect( message[:host] ).to eql('localhost')
      expect( message[:port] ).to eql(25)  
      expect( message[:from] ).to eql('from@example.org')  
    }.and_return(email)

    response = double(response)
    expect(response).to receive(:"respond_to?").with(:code).and_return(true)
    expect(response).to receive(:code).and_return(250)

    expect(EM::Synchrony).to receive(:sync).with(email).and_return(response)

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

    config = {"smtp_config" => {'from' => 'from@example.org', 'reply_to' => 'reply-to@example.com'}}

    Flapjack::Gateways::Email.instance_variable_set('@config', config)
    Flapjack::Gateways::Email.instance_variable_set('@redis', redis)
    Flapjack::Gateways::Email.instance_variable_set('@logger', @logger)
    Flapjack::Gateways::Email.start
    Flapjack::Gateways::Email.perform(notification)
  end  

  it "must default to from address if no reply-to given" do
    email = double('email')
    redis = double('redis')

    expect(EM::P::SmtpClient).to receive(:send) { |message|  
      # NOTE No access to headers directly. Must be determined from message content  
      expect( message[:content] ).to include("Reply-To: from@example.org") 
    }.and_return(email)

    response = double(response)
    expect(response).to receive(:"respond_to?").with(:code).and_return(true)
    expect(response).to receive(:code).and_return(250)

    expect(EM::Synchrony).to receive(:sync).with(email).and_return(response)

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

    config = {"smtp_config" => {'from' => 'from@example.org'}}

    Flapjack::Gateways::Email.instance_variable_set('@config', config)
    Flapjack::Gateways::Email.instance_variable_set('@redis', redis)
    Flapjack::Gateways::Email.instance_variable_set('@logger', @logger)
    Flapjack::Gateways::Email.start
    Flapjack::Gateways::Email.perform(notification)
  end     

  it "sends a mail with text, html parts and default from address" do
    email = double('email')

    entity_check = double(Flapjack::Data::EntityCheck)
    redis = double('redis')

    # TODO better checking of what gets passed here
    expect(EM::P::SmtpClient).to receive(:send).with(
      hash_including(:host    => 'localhost',
                     :port    => 25,
                     :from    => "flapjack@example.com"
                    )).and_return(email)

    response = double(response)
    expect(response).to receive(:"respond_to?").with(:code).and_return(true)
    expect(response).to receive(:code).and_return(250)

    expect(EM::Synchrony).to receive(:sync).with(email).and_return(response)

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
    Flapjack::Gateways::Email.instance_variable_set('@fqdn', "example.com")
    Flapjack::Gateways::Email.perform(notification)
  end

end
