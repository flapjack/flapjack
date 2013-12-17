require 'spec_helper'
require 'flapjack/gateways/sms_messagenet'

describe Flapjack::Gateways::SmsMessagenet, :logger => true do

  let(:lock) { double(Monitor) }

  let(:redis) { double(Redis)}

  let(:config) { {'username'  => 'user',
                  'password'  => 'password'
                 }
               }

  let(:time) { Time.new(2013, 10, 31, 13, 45) }

  let(:time_str) { Time.at(time).strftime('%-d %b %H:%M') }

  let(:message) { {'notification_type' => 'recovery',
                   'contact_first_name' => 'John',
                   'contact_last_name' => 'Smith',
                   'state' => 'ok',
                   'summary' => 'smile',
                   'last_state' => 'problem',
                   'last_summary' => 'frown',
                   'time' => time.to_i,
                   'address' => '555-555555',
                   'event_id' => 'example.com:ping',
                   'id' => '123456789',
                   'duration' => 55,
                   'state_duration' => 23
                  }
                }

  before(:each) do
    allow(Flapjack).to receive(:redis).and_return(redis)
  end

  it "sends an SMS message" do
    expect(Flapjack::Data::Message).to receive(:foreach_on_queue).
      with('sms_notifications', :logger => @logger).
      and_yield(message)
    expect(Flapjack::Data::Message).to receive(:wait_for_queue).
      with('sms_notifications').
      and_raise(Flapjack::PikeletStop)

    req = stub_request(:get, "https://www.messagenet.com.au/dotnet/Lodge.asmx/LodgeSMSMessage").
      with(:query => {'PhoneNumber' => '555-555555',
                      'Username' => 'user',
                      'Pwd' => 'password',
                      'PhoneMessage' => "Recovery: 'ping' on example.com is OK at #{time_str}, smile"}).
      to_return(:status => 200)

    expect(lock).to receive(:synchronize).and_yield

    sms_gw = Flapjack::Gateways::SmsMessagenet.new(:lock => lock,
                                                   :config => config,
                                                   :logger => @logger)
    expect { sms_gw.start }.to raise_error(Flapjack::PikeletStop)
    expect(req).to have_been_requested
  end

  it "truncates a long message a" do
    long_msg = message.merge('summary' => 'Four score and seven years ago our ' +
      'fathers brought forth on this continent, a new nation, conceived in ' +
      'Liberty, and dedicated to the proposition that all men are created equal.')

    expect(Flapjack::Data::Message).to receive(:foreach_on_queue).
      with('sms_notifications', :logger => @logger).
      and_yield(long_msg)
    expect(Flapjack::Data::Message).to receive(:wait_for_queue).
      with('sms_notifications').
      and_raise(Flapjack::PikeletStop)

    req = stub_request(:get, "https://www.messagenet.com.au/dotnet/Lodge.asmx/LodgeSMSMessage").
      with(:query => {'PhoneNumber' => '555-555555',
                      'Username' => 'user',
                      'Pwd' => 'password',
                      'PhoneMessage' => "Recovery: 'ping' on example.com is " +
                        "OK at #{time_str}, Four score and seven years ago " +
                        'our fathers brought forth on this continent, a new ' +
                        'nation, conceived i...'}).
      to_return(:status => 200)

    expect(lock).to receive(:synchronize).and_yield

    sms_gw = Flapjack::Gateways::SmsMessagenet.new(:lock => lock,
                                                   :config => config,
                                                   :logger => @logger)
    expect { sms_gw.start }.to raise_error(Flapjack::PikeletStop)
    expect(req).to have_been_requested
  end

  it "does not send an SMS message with an invalid config" do
    expect(Flapjack::Data::Message).to receive(:foreach_on_queue).
      with('sms_notifications', :logger => @logger).
      and_yield(message)
    expect(Flapjack::Data::Message).to receive(:wait_for_queue).
      with('sms_notifications').
      and_raise(Flapjack::PikeletStop)

    expect(lock).to receive(:synchronize).and_yield

    sms_gw = Flapjack::Gateways::SmsMessagenet.new(:lock => lock,
                                                   :config => config.reject {|k, v| k == 'password'},
                                                   :logger => @logger)
    expect { sms_gw.start }.to raise_error(Flapjack::PikeletStop)

    expect(WebMock).not_to have_requested(:get,
                                      "https://www.messagenet.com.au/dotnet/Lodge.asmx/LodgeSMSMessage")
  end

end