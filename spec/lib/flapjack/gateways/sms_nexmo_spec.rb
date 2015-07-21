require 'spec_helper'
require 'flapjack/gateways/sms_nexmo'

describe Flapjack::Gateways::SmsNexmo, :logger => true do
#   let(:lock) { double(Monitor) }

#   let(:redis) { double('redis') }

#   let(:nexmo_client) { double(Nexmo::Client) }

#   let(:config) { {'api_key' => 'THEAPIKEY',
#                   'secret'  => 'secret',
#                   'from'    => 'flapjack'
#                  }
#                }

#   let(:time) { Time.new(2013, 10, 31, 13, 45) }

#   let(:time_str) { Time.at(time).strftime('%-d %b %H:%M') }

#   let(:message) { {'notification_type'  => 'recovery',
#                    'contact_first_name' => 'John',
#                    'contact_last_name'  => 'Smith',
#                    'state'              => 'ok',
#                    'summary'            => 'smile',
#                    'last_state'         => 'problem',
#                    'last_summary'       => 'frown',
#                    'time'               => time.to_i,
#                    'address'            => '0034123456789',
#                    'event_id'           => 'example.com:ping',
#                    'id'                 => '123456789',
#                    'duration'           => 55,
#                    'state_duration'     => 23
#                   }
#                 }

  it "sends an SMS message" # do
#     EM.synchrony do
#       expect(Flapjack::RedisPool).to receive(:new).and_return(redis)
#       expect(Nexmo::Client).to receive(:new).and_return(nexmo_client)
#       expect(nexmo_client).to receive(:send_message).
#         with(from: "flapjack",
#              to:   "0034123456789",
#              text: "Recovery: 'ping' on example.com is OK at 31 Oct 13:45, smile")

#       alert = Flapjack::Data::Alert.new(message, :logger => @logger)
#       sms_nexmo = Flapjack::Gateways::SmsNexmo.new(:config => config, :logger => @logger)
#       sms_nexmo.deliver(alert)
#       EM.stop
#     end
#   end

  it "does not send an SMS message with an invalid configuration" # do
#     EM.synchrony do
#       expect(Flapjack::RedisPool).to receive(:new).and_return(redis)
#       expect_any_instance_of(Nexmo::Client).not_to receive(:send_message)

#       alert = Flapjack::Data::Alert.new(message, :logger => @logger)
#       sms_nexmo = Flapjack::Gateways::SmsNexmo.new(:config => config.reject {|k, v| k == 'secret'}, :logger => @logger)
#       sms_nexmo.deliver(alert)
#       EM.stop
#     end
#   end
end