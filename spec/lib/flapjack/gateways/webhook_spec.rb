require 'spec_helper'
require 'flapjack/gateways/webhook'

describe Flapjack::Gateways::Webhook, :logger => true do

  let(:lock) { double(Monitor) }

  let(:redis) { double('redis') }

  let(:config) { {'hooks' => [{'url' => 'http://127.0.0.1/flapjack_alert',
                               'timeout' => 30,
                             }],
                 }
               }

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

  it "sends a Webhook message" do
    alert = Flapjack::Data::Alert.new(message, :logger => @logger)

    hash = {}
    alert.instance_variables.each do |var|
      if var.to_s.delete("@") != "logger"
        hash[var.to_s.delete("@")] = alert.instance_variable_get(var)
      end
    end

    notification_id = alert.notification_id
    message_type    = alert.rollup ? 'rollup' : 'alert'
       
    payload_json = Flapjack.dump_json({
     'alert' => hash,
     'id' => notification_id,
     'type' => message_type,
    })

    config['hooks'].each do |hook|
      req = stub_request(:post, hook['url']).
        with(:body => payload_json, :head => {'Content-Type' => 'application/json'}, :inactivity_timeout => hook['timeout']).
        to_return(:status => 200)

      EM.synchrony do
        expect(Flapjack::RedisPool).to receive(:new).and_return(redis)

        webhook = Flapjack::Gateways::Webhook.new(:config => config, :logger => @logger)
        webhook.deliver(alert)
        EM.stop
      end
      expect(req).to have_been_requested
    end
  end

  it "does not send a Webhook message with an invalid config" do
    config['hooks'].each do |hook|
      EM.synchrony do
        expect(Flapjack::RedisPool).to receive(:new).and_return(redis)

        alert = Flapjack::Data::Alert.new(message, :logger => @logger)
        webhook = Flapjack::Gateways::Webhook.new(:config => config.reject {|k, v| k == 'hooks'}, :logger => @logger)
        webhook.deliver(alert)
        EM.stop
      end
      expect(WebMock).not_to have_requested(:post, hook['url'])
    end
  end
end
