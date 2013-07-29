#!/usr/bin/env ruby

require 'em-synchrony'
require 'em-synchrony/em-http'

require 'oj'

require 'flapjack/data/entity_check'
require 'flapjack/data/global'
require 'flapjack/redis_pool'

module Flapjack

  module Gateways

    class Pagerduty
      PAGERDUTY_EVENTS_API_URL   = 'https://events.pagerduty.com/generic/2010-04-15/create_event.json'
      SEM_PAGERDUTY_ACKS_RUNNING = 'sem_pagerduty_acks_running'

      def initialize(opts = {})
        @config = opts[:config]
        @logger = opts[:logger]
        @redis_config = opts[:redis_config] || {}
        @redis = Flapjack::RedisPool.new(:config => @redis_config, :size => 1)

        @logger.debug("New Pagerduty pikelet with the following options: #{@config.inspect}")

        @pagerduty_acks_started = nil
        super()
      end

      def stop
        @logger.info("stopping")
        @should_quit = true
        shutdown_redis = Redis.new(@redis_config.merge(:driver => :hiredis))
        shutdown_redis.rpush(@config['queue'], Oj.dump('notification_type' => 'shutdown'))
      end

      def start
        @logger.info("starting")
        while not test_pagerduty_connection and not @should_quit do
          @logger.error("Can't connect to the pagerduty API, retrying after 10 seconds")
          EM::Synchrony.sleep(10)
        end

        # TODO: only clear this if there isn't another pagerduty gateway instance running
        # or better, include an instance ID in the semaphore key name
        @redis.del(SEM_PAGERDUTY_ACKS_RUNNING)

        acknowledgement_timer = EM::Synchrony.add_periodic_timer(10) do
          find_pagerduty_acknowledgements_if_safe
        end

        queue = @config['queue']
        events = {}

        until @should_quit
          @logger.debug("pagerduty gateway is going into blpop mode on #{queue}")
          events[queue] = @redis.blpop(queue, 0)
          event         = Oj.load(events[queue][1])
          type          = event['notification_type']
          @logger.debug("pagerduty notification event popped off the queue: " + event.inspect)
          unless 'shutdown'.eql?(type)
            event_id      = event['event_id']
            entity, check = event_id.split(':', 2)
            state         = event['state']
            summary       = event['summary']
            address       = event['address']

            headline = type.upcase

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
            when 'test'
              maint_str      = ""
              pagerduty_type = "trigger"
              headline       = "TEST NOTIFICATION"
            end

            message = "#{type.upcase} - \"#{check}\" on #{entity} #{maint_str} - #{summary}"

            pagerduty_event = { :service_key  => address,
                                :incident_key => event_id,
                                :event_type   => pagerduty_type,
                                :description  => message }

            send_pagerduty_event(pagerduty_event)
          end
        end

        acknowledgement_timer.cancel
      end

      # considering this as part of the public API -- exposes it for testing.
      def find_pagerduty_acknowledgements_if_safe

        # ensure we're the only instance of the pagerduty acknowledgement check running (with a naive
        # timeout of five minutes to guard against stale locks caused by crashing code) either in this
        # process or in other processes
        if (@pagerduty_acks_started and @pagerduty_acks_started > (Time.now.to_i - 300)) or
            @redis.get(SEM_PAGERDUTY_ACKS_RUNNING) == 'true'
          @logger.debug("skipping looking for acks in pagerduty as this is already happening")
          return
        end

        @pagerduty_acks_started = Time.now.to_i
        @redis.set(SEM_PAGERDUTY_ACKS_RUNNING, 'true')
        @redis.expire(SEM_PAGERDUTY_ACKS_RUNNING, 300)

        find_pagerduty_acknowledgements

        @redis.del(SEM_PAGERDUTY_ACKS_RUNNING)
        @pagerduty_acks_started = nil
      end

    private

      def test_pagerduty_connection
        noop = { "service_key"  => "11111111111111111111111111111111",
                 "incident_key" => "Flapjack is running a NOOP",
                 "event_type"   => "nop",
                 "description"  => "I love APIs with noops." }
        code, results = send_pagerduty_event(noop)
        return true if code == 200 && results['status'] =~ /success/i
        @logger.error "Error: test_pagerduty_connection: API returned #{code.to_s} #{results.inspect}"
        false
      end

      def send_pagerduty_event(event)
        options  = { :body => Oj.dump(event) }
        http = EM::HttpRequest.new(PAGERDUTY_EVENTS_API_URL).post(options)
        response = Oj.load(http.response)
        status   = http.response_header.status
        @logger.debug "send_pagerduty_event got a return code of #{status.to_s} - #{response.inspect}"
        [status, response]
      end

      def find_pagerduty_acknowledgements
        @logger.debug("looking for acks in pagerduty for unack'd problems")

        unacknowledged_failing_checks = Flapjack::Data::Global.unacknowledged_failing_checks(:redis => @redis)

        @logger.debug "found unacknowledged failing checks as follows: " + unacknowledged_failing_checks.join(', ')

        unacknowledged_failing_checks.each do |entity_check|

          # If more than one contact for this entity_check has pagerduty
          # credentials then there'll be one hash in the array for each set of
          # credentials.
          ec_credentials = entity_check.contacts.inject([]) {|ret, contact|
            cred = contact.pagerduty_credentials
            ret << cred if cred
            ret
          }

          check = entity_check.check

          if ec_credentials.empty?
            @logger.debug("No pagerduty credentials found for #{entity_check.entity_name}:#{check}, skipping")
            next
          end

          # FIXME: try each set of credentials until one works (may have stale contacts turning up)
          options = ec_credentials.first.merge('check' => "#{entity_check.entity_name}:#{check}")

          acknowledged = pagerduty_acknowledged?(options)
          if acknowledged.nil?
            @logger.debug "#{entity_check.entity_name}:#{check} is not acknowledged in pagerduty, skipping"
            next
          end

          pg_acknowledged_by = acknowledged[:pg_acknowledged_by]
          entity_name = entity_check.entity_name
          @logger.info "#{entity_name}:#{check} is acknowledged in pagerduty, creating flapjack acknowledgement... "
          who_text = ""
          if !pg_acknowledged_by.nil? && !pg_acknowledged_by['name'].nil?
            who_text = " by #{pg_acknowledged_by['name']}"
          end
          Flapjack::Data::Event.create_acknowledgement(
            entity_name, check,
            :summary => "Acknowledged on PagerDuty" + who_text,
            :redis => @redis)
        end

      end

      def pagerduty_acknowledged?(opts)
        subdomain   = opts['subdomain']
        username    = opts['username']
        password    = opts['password']
        check       = opts['check']

        t = Time.now.utc

        url = 'https://' + subdomain + '.pagerduty.com/api/v1/incidents'
        query = { 'fields'       => 'incident_number,status,last_status_change_by',
                  'since'        => (t - (60*60*24*7)).iso8601, # the last week
                  'until'        => (t + (60*60*24)).iso8601,   # 1 day in the future
                  'incident_key' => check,
                  'status'       => 'acknowledged' }

        options = { :head  => { 'authorization' => [username, password] },
                    :query => query }

        @logger.debug("pagerduty_acknowledged?: request to #{url}")
        @logger.debug("pagerduty_acknowledged?: query: #{query.inspect}")
        @logger.debug("pagerduty_acknowledged?: auth: #{options[:head].inspect}")

        http = EM::HttpRequest.new(url).get(options)
        begin
          response = Oj.load(http.response)
        rescue Oj::Error
          @logger.error("failed to parse json from a post to #{url} ... response headers and body follows...")
          return nil
        end
        status   = http.response_header.status
        @logger.debug(http.response_header.inspect)
        @logger.debug(http.response)

        @logger.debug("pagerduty_acknowledged?: decoded response as: #{response.inspect}")
        if response.nil?
          @logger.error('no valid response received from pagerduty!')
          return nil
        end

        if response['incidents'].nil?
          @logger.error('no incidents found in response')
          return nil
        end

        return nil if response['incidents'].empty?

        {:pg_acknowledged_by => response['incidents'].first['last_status_change_by']}
      end

    end

  end

end

