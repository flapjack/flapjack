require 'spec_helper'
require 'flapjack/gateways/sms_messagenet'

describe Flapjack::Gateways::SmsMessagenet, :logger => true do

  let(:lock)  { double(Monitor) }
  let(:redis) { double(Redis)}

  let(:config) { {'username'  => 'user',
                  'password'  => 'password'
                 }
               }

  let(:time) { Time.new(2013, 10, 31, 13, 45) }
  let(:time_str) { Time.at(time).strftime('%-d %b %H:%M') }

  let(:queue) { double(Flapjack::RecordQueue) }
  let(:alert) { double(Flapjack::Data::Alert) }

  let(:check) { double(Flapjack::Data::Check) }

  before(:each) do
    Flapjack.stub(:redis).and_return(redis)
  end

  it "sends an SMS message" do
    req = stub_request(:get, "https://www.messagenet.com.au/dotnet/Lodge.asmx/LodgeSMSMessage").
      with(:query => {'PhoneNumber' => '555-555555',
                      'Username' => 'user',
                      'Pwd' => 'password',
                      'PhoneMessage' => "Recovery: 'ping' on example.com is OK at #{time_str}, smile"}).
      to_return(:status => 200)

    Flapjack::RecordQueue.should_receive(:new).with('sms_notifications',
      Flapjack::Data::Alert).and_return(queue)

    medium = double(Flapjack::Data::Medium)
    medium.should_receive(:address).and_return('555-555555')

    alert.should_receive(:medium).and_return(medium)

    alert.should_receive(:id).twice.and_return('123456789')
    alert.should_receive(:rollup).and_return(nil)

    alert.should_receive(:notification_type).and_return('recovery')
    alert.should_receive(:type_sentence_case).and_return('Recovery')
    alert.should_receive(:summary).and_return('smile')

    alert.should_receive(:state_title_case).and_return('OK')
    alert.should_receive(:time).and_return(time.to_i)

    check.should_receive(:entity_name).and_return('example.com')
    check.should_receive(:name).and_return('ping')
    alert.should_receive(:check).and_return(check)

    lock.should_receive(:synchronize).and_yield
    queue.should_receive(:foreach).and_yield(alert)
    queue.should_receive(:wait).and_raise(Flapjack::PikeletStop)

    redis.should_receive(:quit)

    sms_gw = Flapjack::Gateways::SmsMessagenet.new(:lock => lock,
                                                   :config => config,
                                                   :logger => @logger)
    expect { sms_gw.start }.to raise_error(Flapjack::PikeletStop)
    req.should have_been_requested
  end

  it "truncates a long message" do
     long_summary = 'Four score and seven years ago our ' +
       'fathers brought forth on this continent, a new nation, conceived in ' +
       'Liberty, and dedicated to the proposition that all men are created equal.'

    req = stub_request(:get, "https://www.messagenet.com.au/dotnet/Lodge.asmx/LodgeSMSMessage").
      with(:query => {'PhoneNumber' => '555-555555',
                      'Username' => 'user',
                      'Pwd' => 'password',
                      'PhoneMessage' => "Recovery: 'ping' on example.com is " +
                        "OK at #{time_str}, Four score and seven years ago " +
                        'our fathers brought forth on this continent, a new ' +
                        'nation, conceived i...'}).
      to_return(:status => 200)

    medium = double(Flapjack::Data::Medium)
    medium.should_receive(:address).and_return('555-555555')

    alert.should_receive(:medium).and_return(medium)

    alert.should_receive(:id).twice.and_return('123456789')
    alert.should_receive(:rollup).and_return(nil)

    alert.should_receive(:notification_type).and_return('recovery')
    alert.should_receive(:type_sentence_case).and_return('Recovery')
    alert.should_receive(:summary).and_return(long_summary)

    alert.should_receive(:state_title_case).and_return('OK')
    alert.should_receive(:time).and_return(time.to_i)

    check.should_receive(:entity_name).and_return('example.com')
    check.should_receive(:name).and_return('ping')
    alert.should_receive(:check).and_return(check)

    Flapjack::RecordQueue.should_receive(:new).with('sms_notifications',
      Flapjack::Data::Alert).and_return(queue)

    lock.should_receive(:synchronize).and_yield
    queue.should_receive(:foreach).and_yield(alert)
    queue.should_receive(:wait).and_raise(Flapjack::PikeletStop)

    redis.should_receive(:quit)

    sms_gw = Flapjack::Gateways::SmsMessagenet.new(:lock => lock,
                                                   :config => config,
                                                   :logger => @logger)
    expect { sms_gw.start }.to raise_error(Flapjack::PikeletStop)
    req.should have_been_requested
  end

  it "does not send an SMS message with an invalid config" do
    Flapjack::RecordQueue.should_receive(:new).with('sms_notifications',
      Flapjack::Data::Alert).and_return(queue)

    medium = double(Flapjack::Data::Medium)
    medium.should_receive(:address).and_return('555-555555')

    alert.should_receive(:medium).and_return(medium)

    alert.should_receive(:id).and_return('123456789')
    alert.should_receive(:rollup).and_return(nil)

    alert.should_receive(:notification_type).and_return('recovery')
    alert.should_receive(:type_sentence_case).and_return('Recovery')
    alert.should_receive(:summary).and_return('smile')

    alert.should_receive(:state_title_case).and_return('OK')
    alert.should_receive(:time).and_return(time.to_i)

    check.should_receive(:entity_name).and_return('example.com')
    check.should_receive(:name).and_return('ping')
    alert.should_receive(:check).and_return(check)

    lock.should_receive(:synchronize).and_yield
    queue.should_receive(:foreach).and_yield(alert)
    queue.should_receive(:wait).and_raise(Flapjack::PikeletStop)

    redis.should_receive(:quit)

    sms_gw = Flapjack::Gateways::SmsMessagenet.new(:lock => lock,
                                                   :config => config.reject {|k, v| k == 'password'},
                                                   :logger => @logger)
    expect { sms_gw.start }.to raise_error(Flapjack::PikeletStop)

    WebMock.should_not have_requested(:get,
                                      "https://www.messagenet.com.au/dotnet/Lodge.asmx/LodgeSMSMessage")
  end

end