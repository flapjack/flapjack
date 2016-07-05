require 'spec_helper'
require 'flapjack/gateways/hipchat'

describe Flapjack::Gateways::Hipchat, :logger => true do

  let(:lock) { double(Monitor) }

  let(:redis) { double('redis') }
  
  let(:config) { {
    'username'     => 'Hipchat User',
    'api_token'    => 'xxxxxxxxxxxx',
    'room'         => 'flapjack-hipchat-test'
  } }
  
  let(:time) { Time.new(2013, 10, 31, 13, 45) }

  let(:time_str) { Time.at(time).strftime('%-d %b %H:%M') }

  let(:message) { {'notification_type'  => 'recovery',
                   'contact_first_name' => 'John',
                   'contact_last_name'  => 'Smith',
                   'state'              => 'ok',
                   'summary'            => 'smile',
                   'last_state'         => 'problem',
                   'last_summary'       => 'frown',
                   'time'               => time.to_i,
                   'address'            => 'general',
                   'event_id'           => 'example.com:ping',
                   'id'                 => '123456789',
                   'duration'           => 55,
                   'state_duration'     => 23
                  }
                }

  it "sends a Hipchat message" do
    expected_payload = Flapjack.dump_json(
      'room_id'           => 'flapjack-hipchat-test',
      'from'              => 'Hipchat User',
      'color'             => 'green',
      'notify'            => false,
      'message_format'    => 'html',
      'message'           => "Recovery: 'ping' on example.com is OK at #{time_str}, smile"
    )

   req = stub_request(:post, %r{\Ahttps://api.hipchat.com/v2/room/flapjack-hipchat-test/notification\?auth_token=(.*)\z}).
      with(
        :body => "{\"room_id\":\"flapjack-hipchat-test\",\"from\":\"Hipchat User\",\"message\":\"Recovery: 'ping' on example.com is OK at 31 Oct 13:45, smile\",\"message_format\":\"html\",\"color\":\"green\",\"notify\":false}",
        :headers => {'Accept'=>'application/json', 'Content-Type'=>'application/json'}
      ).to_return(:status => 200, :body => "", :headers => {})
                
    EM.synchrony do
      expect(Flapjack::RedisPool).to receive(:new).and_return(redis)

      alert = Flapjack::Data::Alert.new(message, :logger => @logger)
      hipchat = Flapjack::Gateways::Hipchat.new(:config => config, :logger => @logger)
      hipchat.deliver(alert)
      EM.stop
    end
    expect(req).to have_been_requested
  end

  it "does not send a Hipchat message with an invalid config" do
    EM.synchrony do
      expect(Flapjack::RedisPool).to receive(:new).and_return(redis)

      alert = Flapjack::Data::Alert.new(message, :logger => @logger)
      hipchat = Flapjack::Gateways::Hipchat.new(:config => config.reject {|k, v| k == 'api_token'}, :logger => @logger)
      hipchat.deliver(alert)
      EM.stop
    end

    expect(WebMock).not_to have_requested(:post, config['api_token'])
  end
end