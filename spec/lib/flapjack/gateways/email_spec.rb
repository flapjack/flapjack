require 'spec_helper'
require 'flapjack/gateways/email'

describe Flapjack::Gateways::Email, :logger => true do

  let(:client) { double('client') }
  let(:redis) { double('redis') }

  it "can have a custom from email address" do
    expect(EM::P::SmtpClient).to receive(:send).with(
      hash_including(host: 'localhost',
                     port: 25,
                     from: "from@example.org")
    ).and_return(client)

    response = double(response)
    expect(response).to receive(:"respond_to?").with(:code).and_return(true)
    expect(response).to receive(:code).and_return(250)

    expect(EM::Synchrony).to receive(:sync).with(client).and_return(response)

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

    EM.synchrony do
      expect(Flapjack::RedisPool).to receive(:new).and_return(redis)

      alert = Flapjack::Data::Alert.new(notification, :logger => @logger)
      email = Flapjack::Gateways::Email.new(:config => config, :logger => @logger)
      email.deliver(alert)
      EM.stop
    end
  end

  it "can have a full name in custom from email address" do
    expect(EM::P::SmtpClient).to receive(:send).with(
      hash_including(host: 'localhost',
                     port: 25,
                     from: "from@example.org")
    ).and_return(client)

    response = double(response)
    expect(response).to receive(:"respond_to?").with(:code).and_return(true)
    expect(response).to receive(:code).and_return(250)

    expect(EM::Synchrony).to receive(:sync).with(client).and_return(response)

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

    config = {"smtp_config" => {'from' => 'Full Name <from@example.org>'}}

    EM.synchrony do
      expect(Flapjack::RedisPool).to receive(:new).and_return(redis)

      alert = Flapjack::Data::Alert.new(notification, :logger => @logger)
      email = Flapjack::Gateways::Email.new(:config => config, :logger => @logger)
      email.deliver(alert)
      EM.stop
    end
  end

  it "can have a custom reply-to address" do
    expect(EM::P::SmtpClient).to receive(:send) { |message|
      # NOTE No access to headers directly. Must be determined from message content
      expect( message[:content] ).to include("Reply-To: reply-to@example.com")
      # NOTE Ensure we haven't trashed any other arguments
      expect( message[:host] ).to eql('localhost')
      expect( message[:port] ).to eql(25)
      expect( message[:from] ).to eql('from@example.org')
    }.and_return(client)

    response = double(response)
    expect(response).to receive(:"respond_to?").with(:code).and_return(true)
    expect(response).to receive(:code).and_return(250)

    expect(EM::Synchrony).to receive(:sync).with(client).and_return(response)

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

    EM.synchrony do
      expect(Flapjack::RedisPool).to receive(:new).and_return(redis)

      alert = Flapjack::Data::Alert.new(notification, :logger => @logger)
      email = Flapjack::Gateways::Email.new(:config => config, :logger => @logger)
      email.deliver(alert)
      EM.stop
    end
  end

  it "must default to from address if no reply-to given" do
    expect(EM::P::SmtpClient).to receive(:send) { |message|
      # NOTE No access to headers directly. Must be determined from message content
      expect( message[:content] ).to include("Reply-To: from@example.org")
    }.and_return(client)

    response = double(response)
    expect(response).to receive(:"respond_to?").with(:code).and_return(true)
    expect(response).to receive(:code).and_return(250)

    expect(EM::Synchrony).to receive(:sync).with(client).and_return(response)

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

    EM.synchrony do
      expect(Flapjack::RedisPool).to receive(:new).and_return(redis)

      alert = Flapjack::Data::Alert.new(notification, :logger => @logger)
      email = Flapjack::Gateways::Email.new(:config => config, :logger => @logger)
      email.deliver(alert)
      EM.stop
    end
  end

  it "sends a mail with text, html parts and default from address" do
    entity_check = double(Flapjack::Data::EntityCheck)

    # TODO better checking of what gets passed here
    expect(EM::P::SmtpClient).to receive(:send).with(
      hash_including(:host    => 'localhost',
                     :port    => 25,
                     :from    => "flapjack@example.com"
                    )).and_return(client)

    response = double(response)
    expect(response).to receive(:"respond_to?").with(:code).and_return(true)
    expect(response).to receive(:code).and_return(250)

    expect(EM::Synchrony).to receive(:sync).with(client).and_return(response)

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

    EM.synchrony do
      expect(Flapjack::RedisPool).to receive(:new).and_return(redis)

      alert = Flapjack::Data::Alert.new(notification, :logger => @logger)
      email = Flapjack::Gateways::Email.new(:config => {}, :logger => @logger)
      email.instance_variable_set('@fqdn', "example.com")
      email.deliver(alert)
      EM.stop
    end
  end

end
