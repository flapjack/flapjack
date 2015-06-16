require 'spec_helper'
require 'flapjack/gateways/aws_sns'

describe Flapjack::Gateways::AwsSns, :logger => true do

  let(:lock) { double(Monitor) }

  let(:redis) { double('redis') }

  let(:time_int) { 1383252300 }

  let(:time_str) { '2013-10-31T20:45:00Z' }

  let(:config) { {'region' => 'us-east-1',
                  'access_key' => 'AKIAIOSFODNN7EXAMPLE',
                  'secret_key' => 'secret'
                 }
               }

  let(:message) { {'notification_type'  => 'recovery',
                   'contact_first_name' => 'John',
                   'contact_last_name'  => 'Smith',
                   'state'              => 'ok',
                   'summary'            => 'smile',
                   'last_state'         => 'problem',
                   'last_summary'       => 'frown',
                   'time'               => time_int,
                   'address'            => 'arn:aws:sns:us-east-1:698519295917:My-Topic',
                   'event_id'           => 'example.com:ping',
                   'id'                 => '123456789',
                   'duration'           => 55,
                   'state_duration'     => 23
                  }
                }

  it "sends an SMS message" do
    # bad, bad, bad...
    t = double('time')
    ut  = double('utc_time')
    expect(ut).to receive(:strftime).with('%Y-%m-%dT%H:%M:%SZ').and_return(time_str)
    expect(t).to receive(:utc).and_return(ut)
    expect(t).to receive(:strftime).with('%-d %b %H:%M').and_return('31 Oct 20:45')
    expect(Time).to receive(:at).with(time_int).twice.and_return(t)

    req = stub_request(:post, "http://sns.us-east-1.amazonaws.com/").
      with(:query => hash_including({'Action'           => 'Publish',
                                     'AWSAccessKeyId'   => config['access_key'],
                                     'TopicArn'         => message['address'],
                                     'SignatureVersion' => '2',
                                     'SignatureMethod'  => 'HmacSHA256',
                                     'Signature'        => '5fWqhmDrZQkQfP7wsxWDdQjzV0BLwm6cZNrNqZ+W/ok=',
                                     'Timestamp'        => time_str})).
      to_return(:status => 200)

    EM.synchrony do
      expect(Flapjack::RedisPool).to receive(:new).and_return(redis)

      alert = Flapjack::Data::Alert.new(message, :logger => @logger)
      aws_sns = Flapjack::Gateways::AwsSns.new(:config => config, :logger => @logger)
      aws_sns.deliver(alert)
      EM.stop
    end
    expect(req).to have_been_requested
  end

  it 'truncates an overly long subject when sending' do
    req = stub_request(:post, "http://sns.us-east-1.amazonaws.com/").
      with(:query => hash_including({'Action'           => 'Publish',
                                     'AWSAccessKeyId'   => config['access_key'],
                                     'TopicArn'         => message['address'],
                                     'SignatureVersion' => '2',
                                     'SignatureMethod'  => 'HmacSHA256',
                                     'Subject'          => "Recovery: '#{'1234567890' * 8}123456..."})).
      to_return(:status => 200)

    EM.synchrony do
      expect(Flapjack::RedisPool).to receive(:new).and_return(redis)

      long_event_id = "example.com:#{'1234567890' * 10}"
      alert = Flapjack::Data::Alert.new(message.merge('event_id' => long_event_id), :logger => @logger)
      aws_sns = Flapjack::Gateways::AwsSns.new(:config => config, :logger => @logger)
      aws_sns.deliver(alert)
      EM.stop
    end
    expect(req).to have_been_requested
  end

  it "does not send an SMS message with an invalid config" do
    EM.synchrony do
      expect(Flapjack::RedisPool).to receive(:new).and_return(redis)

      alert = Flapjack::Data::Alert.new(message, :logger => @logger)
      aws_sns = Flapjack::Gateways::AwsSns.new(:config => config.reject {|k, v| k == 'secret_key'}, :logger => @logger)
      aws_sns.deliver(alert)
      EM.stop
    end

    expect(WebMock).not_to have_requested(:get, "http://sns.us-east-1.amazonaws.com/")
  end

  context "#string_to_sign" do

    let(:method) { 'post' }

    let(:host) { 'sns.us-east-1.AmazonAWS.com' }

    let(:uri) { '/' }

    let(:query) { {'TopicArn' => 'HelloWorld',
                   'Action' => 'Publish',
                   'Message' => 'Hello ~ World'} }

    let(:string_to_sign) { Flapjack::Gateways::AwsSns.string_to_sign(method, host, uri, query) }

    let(:lines) { string_to_sign.split(/\n/) }

    it 'should put the method on the first line' do
      expect(lines[0]).to eq("POST")
    end

    it 'should put the downcased hostname on the second line' do
      expect(lines[1]).to eq("sns.us-east-1.amazonaws.com")
    end

    it 'should put the URI on the third line' do
      expect(lines[2]).to eq("/")
    end

    it 'should put the encoded, sorted query-string on the fourth line' do
      expect(lines[3]).to eq("Action=Publish&Message=Hello%20~%20World&TopicArn=HelloWorld")
    end

  end

  context "#get_signature" do
    let(:method) { 'GET' }

    let(:host) { 'elasticmapreduce.amazonaws.com' }

    let(:uri) { '/' }

    let(:query) { {'AWSAccessKeyId' => 'AKIAIOSFODNN7EXAMPLE',
                   'Action' => 'DescribeJobFlows',
                   'SignatureMethod' => 'HmacSHA256',
                   'SignatureVersion' => '2',
                   'Timestamp' => '2011-10-03T15:19:30',
                   'Version' => '2009-03-31'} }

    let(:secret_key) { 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY' }

    let(:string_to_sign) { Flapjack::Gateways::AwsSns.string_to_sign(method, host, uri, query) }

    let(:signature) { Flapjack::Gateways::AwsSns.get_signature(secret_key, string_to_sign) }

    it 'should HMAC-SHA256 and base64 encode the signature' do
      expect(signature).to eq("i91nKc4PWAt0JJIdXwz9HxZCJDdiy6cf/Mj6vPxyYIs=")
    end
  end

end
