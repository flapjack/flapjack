require 'spec_helper'
require 'flapjack/gateways/slack'

describe Flapjack::Gateways::Slack, :logger => true do

#   let(:lock) { double(Monitor) }

#   let(:redis) { double('redis') }

#   let(:config) { {'account_sid' => 'flapslack',
#                   'endpoint'    => 'https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX'
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
#                    'address'            => 'general',
#                    'event_id'           => 'example.com:ping',
#                    'id'                 => '123456789',
#                    'duration'           => 55,
#                    'state_duration'     => 23
#                   }
#                 }

  it "sends a Slack message" # do
#     payload_json = Flapjack.dump_json(
#       'channel'    => '#general',
#       'username'   => 'flapslack',
#       'text'       => "Recovery: 'ping' on example.com is OK at #{time_str}, smile",
#       'icon_emoji' => ':ghost:'
#     )

#     req = stub_request(:post, config['endpoint']).
#       with(:body => {'payload' => payload_json}).
#       to_return(:status => 200)

#     EM.synchrony do
#       expect(Flapjack::RedisPool).to receive(:new).and_return(redis)

#       alert = Flapjack::Data::Alert.new(message, :logger => @logger)
#       slack = Flapjack::Gateways::Slack.new(:config => config, :logger => @logger)
#       slack.deliver(alert)
#       EM.stop
#     end
#     expect(req).to have_been_requested
#   end

  it "does not send a Slack message with an invalid config" # do
#     EM.synchrony do
#       expect(Flapjack::RedisPool).to receive(:new).and_return(redis)

#       alert = Flapjack::Data::Alert.new(message, :logger => @logger)
#       slack = Flapjack::Gateways::Slack.new(:config => config.reject {|k, v| k == 'endpoint'}, :logger => @logger)
#       slack.deliver(alert)
#       EM.stop
#     end

#     expect(WebMock).not_to have_requested(:post, config['endpoint'])
#   end

end