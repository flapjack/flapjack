require 'spec_helper'
require 'flapjack/gateways/aws_sns'

describe Flapjack::Gateways::AwsSns, :logger => true do

  let(:lock)  { double(Monitor) }
  let(:redis) { double(Redis)}

  let(:queue) { double(Flapjack::RecordQueue) }
  let(:alert) { double(Flapjack::Data::Alert) }

  let(:time) { Time.new(2013, 10, 31, 13, 45) }

  let(:time_str) { Time.at(time).strftime('%-d %b %H:%M') }

  let(:config) { {'region' => 'us-east-1',
                  'access_key' => 'AKIAIOSFODNN7EXAMPLE',
                  'secret_key' => 'secret'
                 }
               }

  let(:message) { {'notification_type'  => 'recovery',
                   'contact_name' => 'John Smith',
                   'state'              => 'ok',
                   'summary'            => 'smile',
                   'last_state'         => 'problem',
                   'last_summary'       => 'frown',
                   'time'               => time.to_i,
                   'event_id'           => 'example.com:ping',
                   'id'                 => '123456789',
                   'duration'           => 55,
                   'condition_duration'     => 23
                  }
                }

  let(:address) { 'arn:aws:sns:us-east-1:698519295917:My-Topic' }

  let(:check)  { double(Flapjack::Data::Check) }

  before(:each) do
    allow(Flapjack).to receive(:redis).and_return(redis)
  end

 # it "sends an SMS message" do
 #   # bad, bad, bad...
 #   t = double('time')
 #   ut  = double('utc_time')
 #   expect(ut).to receive(:strftime).with('%Y-%m-%dT%H:%M:%SZ').and_return(time_str)
 #   expect(t).to receive(:utc).and_return(ut)
 #   expect(t).to receive(:strftime).with('%-d %b %H:%M').and_return('31 Oct 20:45')
 #   expect(Time).to receive(:at).with(time_int).twice.and_return(t)

 #   req = stub_request(:post, "http://sns.us-east-1.amazonaws.com/").
 #     with(:query => hash_including({'Action'           => 'Publish',
 #                                    'AWSAccessKeyId'   => config['access_key'],
 #                                    'TopicArn'         => message['address'],
 #                                    'SignatureVersion' => '2',
 #                                    'SignatureMethod'  => 'HmacSHA256',
 #                                    'Signature'        => '5fWqhmDrZQkQfP7wsxWDdQjzV0BLwm6cZNrNqZ+W/ok=',
 #                                    'Timestamp'        => time_str})).
 #     to_return(:status => 200)

 #   EM.synchrony do
 #     expect(Flapjack::RedisPool).to receive(:new).and_return(redis)

 #     alert = Flapjack::Data::Alert.new(message, :logger => @logger)
 #     aws_sns = Flapjack::Gateways::AwsSns.new(:config => config, :logger => @logger)
 #     aws_sns.deliver(alert)
 #     EM.stop
 #   end
 #   expect(req).to have_been_requested
 # end

 it 'truncates an overly long subject when sending' # FIXME port from maint/1.x

  it "sends an SMS message" do
    req = stub_request(:post, "http://sns.us-east-1.amazonaws.com/").
      with(:body => hash_including({'Action'           => 'Publish',
                                    'AWSAccessKeyId'   => config['access_key'],
                                    'TopicArn'         => address,
                                    'SignatureVersion' => '2',
                                    'SignatureMethod'  => 'HmacSHA256'})).
      to_return(:status => 200)

    expect(Flapjack::RecordQueue).to receive(:new).with('sns_notifications',
      Flapjack::Data::Alert).and_return(queue)

    expect(lock).to receive(:synchronize).and_yield
    expect(queue).to receive(:foreach).and_yield(alert)
    expect(queue).to receive(:wait).and_raise(Flapjack::PikeletStop)

    medium = double(Flapjack::Data::Medium)
    expect(medium).to receive(:address).and_return(address)

    expect(alert).to receive(:medium).and_return(medium)
    expect(alert).to receive(:id).and_return('123456789')
    expect(alert).to receive(:rollup).and_return(nil)

    expect(alert).to receive(:type).and_return('recovery')
    expect(alert).to receive(:notification_type).and_return('recovery')
    expect(alert).to receive(:type_sentence_case).twice.and_return('Recovery')
    expect(alert).to receive(:summary).and_return('smile')

    expect(check).to receive(:name).twice.and_return('example.com:ping')
    expect(alert).to receive(:check).and_return(check)

    expect(alert).to receive(:state_title_case).twice.and_return('OK')
    expect(alert).to receive(:time).twice.and_return(time)

    expect(redis).to receive(:quit)

    sns_gw = Flapjack::Gateways::AwsSns.new(:lock => lock,
                                            :config => config)
    expect { sns_gw.start }.to raise_error(Flapjack::PikeletStop)
    expect(req).to have_been_requested
  end

  it "does not send an SMS message with an invalid config" do
    expect(Flapjack::RecordQueue).to receive(:new).with('sns_notifications',
      Flapjack::Data::Alert).and_return(queue)

    expect(lock).to receive(:synchronize).and_yield
    expect(queue).to receive(:foreach).and_yield(alert)
    expect(queue).to receive(:wait).and_raise(Flapjack::PikeletStop)

    medium = double(Flapjack::Data::Medium)
    expect(medium).to receive(:address).and_return(address)

    expect(alert).to receive(:medium).and_return(medium)
    expect(alert).to receive(:id).and_return('123456789')
    expect(alert).to receive(:rollup).and_return(nil)

    expect(alert).to receive(:type).and_return('recovery')
    expect(alert).to receive(:notification_type).and_return('recovery')
    expect(alert).to receive(:type_sentence_case).twice.and_return('Recovery')
    expect(alert).to receive(:summary).and_return('smile')

    expect(check).to receive(:name).twice.and_return('example.com:ping')
    expect(alert).to receive(:check).and_return(check)

    expect(alert).to receive(:state_title_case).twice.and_return('OK')
    expect(alert).to receive(:time).twice.and_return(time)

    expect(redis).to receive(:quit)

    sns_gw = Flapjack::Gateways::AwsSns.new(:lock => lock,
                                            :config => config.reject {|k, v| k == 'secret_key'})

    expect { sns_gw.start }.to raise_error(Flapjack::PikeletStop)
    expect(WebMock).not_to have_requested(:get, "http://sns.us-east-1.amazonaws.com/")
  end

  context "#string_to_sign" do

    let(:method) { 'post' }

    let(:host) { 'sns.us-east-1.AmazonAWS.com' }

    let(:uri) { '/' }

    let(:query) { {'TopicArn' => 'HelloWorld',
                  'Action' => 'Publish'} }

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
      expect(lines[3]).to eq("Action=Publish&TopicArn=HelloWorld")
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
