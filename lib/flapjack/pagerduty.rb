#!/usr/bin/env ruby

require 'eventmachine'
# the redis/synchrony gems need to be required in this particular order, see
# the redis-rb README for details
require 'hiredis'
require 'em-synchrony'
require 'redis/connection/synchrony'
require 'redis'

require 'httparty'
#require 'em-synchrony/fiber_iterator'
require 'yajl/json_gem'

require 'flapjack/data/entity_check'
require 'flapjack/pikelet'

module Flapjack

  class Pagerduty

    include Flapjack::Pikelet
    include HTTParty

    # in case of emergency pull handle
    #debug_output

    def initialize(opts = {})
      super()
      self.bootstrap

      @config = opts[:config] ? opts[:config].dup : {}
      logger.debug("New Pagerduty pikelet with the following options: #{opts.inspect}")

      @redis = opts[:redis]
      @redis_config = opts[:redis_config]

      @pagerduty_events_api_url = 'https://events.pagerduty.com/generic/2010-04-15/create_event.json'
    end

    def send_pagerduty_event(event)
      options  = { :body => Yajl::Encoder.encode(event) }
      response = self.class.post(@pagerduty_events_api_url, options)
      logger.debug "send_pagerduty_event got a return code of #{response.code.to_s} - #{response.to_s}"
      return response.code, response.to_hash
    end

    def test_pagerduty_connection
      noop = { "service_key"  => "11111111111111111111111111111111",
               "incident_key" => "Flapjack is running a NOOP",
               "event_type"   => "nop",
               "description"  => "I love APIs with noops." }
      code, results = send_pagerduty_event(noop)
      return true if code == 200
      logger.error "Error: test_pagerduty_connection: API returned #{code.to_s} #{resuls.inspect}"
      return false
    end

    def list_pagerduty_incidents(opts)
      subdomain   = opts[:subdomain]
      username    = opts[:username]
      password    = opts[:password]
    end

    def add_shutdown_event
      r = ::Redis.new(@redis_config)
      r.rpush(@config['queue'], JSON.generate('notification_type' => 'shutdown'))
      r.quit
    end

    def main
      logger.debug("pagerduty gateway - commencing main method")
      raise "Can't connect to the pagerduty API" unless test_pagerduty_connection
      queue = @config['queue']
      events = {}
      until should_quit?
          logger.debug("pagerduty gateway is going into blpop mode on #{queue}")
          events[queue] = @redis.blpop(queue)
          event         = Yajl::Parser.parse(events[queue][1])
          type          = event['notification_type']
          logger.debug("pagerduty notification event popped off the queue: " + event.inspect)
          if 'shutdown'.eql?(type)
            # do anything in particular?
          else
            event_id      = event['event_id']
            entity, check = event_id.split(':')
            state         = event['state']
            summary       = event['summary']
            address       = event['address']

            case type.downcase
            when 'acknowledgement'
              maint_str      = "has been acknowledged"
              pagerduty_type = 'acknowledge'
            when 'problem'
              maint_str      = "is #{state.upcase}"
              pagerduty_type = "trigger"
            when 'recovery'
              maint_str      = "is #{state.upcase}"
              pagerduty_type = "resolve"
            end

            message = "#{type.upcase} - \"#{check}\" on #{entity} #{maint_str} - #{summary}"

            pagerduty_event = { :service_key  => address,
                                :incident_key => event_id,
                                :event_type   => pagerduty_type,
                                :description  => message }

            send_pagerduty_event(pagerduty_event)

          end
      end
    end

  end
end

