require 'spec_helper'
require 'flapjack/gateways/sms_messagenet'

describe Flapjack::Gateways::SmsMessagenet, :logger => true do

    let(:config) { {'username'  => 'user',
                    'password'  => 'password'
                   }
                 }

    let(:message) { {'notification_type'  => 'recovery',
                     'contact_first_name' => 'John',
                     'contact_last_name'  => 'Smith',
                     'state'              => 'ok',
                     'summary'            => 'smile',
                     'last_state'         => 'problem',
                     'last_summary'       => 'frown',
                     'time'               => Time.now.to_i,
                     'address'            => '555-555555',
                     'event_id'           => 'example.com:ping',
                     'id'                 => '123456789'
                    }
                  }

  it "sends an SMS message" do
    redis = mock('redis')
    ::Redis.should_receive(:new).and_return(redis)

    Flapjack::Data::Message.should_receive(:foreach_on_queue).
      with('sms_notifications', :redis => redis, :logger => @logger).
      and_yield(message)
    Flapjack::Data::Message.should_receive(:wait_for_queue).
      with('sms_notifications', :redis => redis).
      and_raise(Flapjack::PikeletStop)

    req = stub_request(:get, "https://www.messagenet.com.au/dotnet/Lodge.asmx/LodgeSMSMessage").
      with(:query => hash_including({'PhoneNumber' => '555-555555',
                                     'Username' => 'user', 'Pwd' => 'password'})).
      to_return(:status => 200)

    sms_gw = Flapjack::Gateways::SmsMessagenet.new(:config => config,
                                                   :logger => @logger)
    expect { sms_gw.start }.to raise_error(Flapjack::PikeletStop)
    req.should have_been_requested
  end

  it "does not send an SMS message with an invalid config" do
    redis = mock('redis')
    ::Redis.should_receive(:new).and_return(redis)

    Flapjack::Data::Message.should_receive(:foreach_on_queue).
      with('sms_notifications', :redis => redis, :logger => @logger).
      and_yield(message)
    Flapjack::Data::Message.should_receive(:wait_for_queue).
      with('sms_notifications', :redis => redis).
      and_raise(Flapjack::PikeletStop)

    sms_gw = Flapjack::Gateways::SmsMessagenet.new(:config => config.reject {|k, v| k == 'password'},
                                                   :logger => @logger)
    expect { sms_gw.start }.to raise_error(Flapjack::PikeletStop)

    WebMock.should_not have_requested(:get,
                                      "https://www.messagenet.com.au/dotnet/Lodge.asmx/LodgeSMSMessage")
  end

end