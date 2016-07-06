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
                
  # let(:expected_payload) {
  #   Flapjack.dump_json(
  #     'room_id'           => 'flapjack-hipchat-test',
  #     'from'              => 'Hipchat User',
  #     'color'             => 'green',
  #     'notify'            => false,
  #     'message_format'    => 'html',
  #     'message'           => "Recovery: 'ping' on example.com is OK at #{time_str}, smile"
  #   )
  # }
  
  let!(:req) {
    stub_request(:post, "https://api.hipchat.com/v2/room/flapjack-hipchat-test/notification?auth_token=xxxxxxxxxxxx").
             with(:body => "{\"room_id\":\"flapjack-hipchat-test\",\"from\":\"Hipchat User\",\"message\":\"Recovery: 'ping' on example.com is OK at 31 Oct 13:45, smile\",\"message_format\":\"text\",\"color\":\"green\",\"notify\":false}",
                  :headers => {'Accept'=>'application/json', 'Content-Type'=>'application/json'}).
             to_return(:status => 200, :body => "", :headers => {})
  }

  it "sends a Hipchat message" do

    EM.synchrony do
      expect(Flapjack::RedisPool).to receive(:new).and_return(redis)

      alert = Flapjack::Data::Alert.new(message, :logger => @logger)
      hipchat = Flapjack::Gateways::Hipchat.new(:config => config, :logger => @logger)
      hipchat.deliver(alert)
      EM.stop
    end
    expect(req).to have_been_requested
  end

  # NOTE Implemented - just needs to be tested
  it "sends a Hipchat rollup message if rollups enabled" do
    req = stub_request(:post, "https://api.hipchat.com/v2/room/flapjack-hipchat-test/notification?auth_token=xxxxxxxxxxxx").
         with(:body => "{\"room_id\":\"flapjack-hipchat-test\",\"from\":\"Hipchat User\",\"message\":\"Problem summaries finishing: Critical: 51, Warning: 5, Unknown: 32 (Critical: xyz-dvmh-so-04.cust.bulletproof.net:HTTPS - schedule.abc.com.au)\",\"message_format\":\"text\",\"color\":\"green\",\"notify\":false}",
              :headers => {'Accept'=>'application/json', 'Content-Type'=>'application/json'}).
         to_return(:status => 200, :body => "", :headers => {})
         
    EM.synchrony do

      expect(Flapjack::RedisPool).to receive(:new).and_return(redis)

      alert = Flapjack::Data::Alert.new(message.merge('rollup' => 'recovery'), :logger => @logger)

      alert.stub(:rollup_states_summary).and_return("Critical: 51, Warning: 5, Unknown: 32")

      alert.stub(:rollup_states_detail_text).and_return(
        "Critical: xyz-dvmh-so-04.cust.bulletproof.net:HTTPS - schedule.abc.com.au"
      )

      hipchat = Flapjack::Gateways::Hipchat.new(:config => config.merge('enable_rollups' => true), :logger => @logger)
      hipchat.deliver(alert)
      EM.stop
    end
    expect(req).to have_been_requested
  end
  
  it "does not send a Hipchat rollup message if rollups disabled" do
    EM.synchrony do
      expect(Flapjack::RedisPool).to receive(:new).and_return(redis)

      alert = Flapjack::Data::Alert.new(message.merge('rollup' => 'recovery'), :logger => @logger)
      hipchat = Flapjack::Gateways::Hipchat.new(:config => config.merge('enable_rollups' => false), :logger => @logger)
      hipchat.deliver(alert)
      EM.stop
    end
    expect(req).to_not have_been_requested
  end
  
  it "does not initialize Hipchat gateway with an invalid config" do
    EM.synchrony do
      expect(Flapjack::RedisPool).to receive(:new).and_return(redis)

      hipchat = Flapjack::Gateways::Hipchat.new(:config => config.reject {|k, v| k == 'api_token'}, :logger => @logger)
      expect(@logger.messages).to include("ERROR: Hipchat api_token is missing") 
      EM.stop
    end

  end
end