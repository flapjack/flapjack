#!/usr/bin/env ruby

require 'em-hiredis'
require 'em-synchrony'
require 'em-synchrony/em-http'

require 'oj'

require 'flapjack/data/entity_check'
require 'flapjack/data/alert'
require 'flapjack/redis_pool'
require 'flapjack/utility'

module Flapjack

  module Gateways

    class Pagerduty
      PAGERDUTY_EVENTS_API_URL   = 'https://events.pagerduty.com/generic/2010-04-15/create_event.json'
      SEM_PAGERDUTY_ACKS_RUNNING = 'sem_pagerduty_acks_running'

      include Flapjack::Utility

      def initialize(opts = {})
        @config = opts[:config]
        @logger = opts[:logger]
        @redis_config = opts[:redis_config] || {}
        @redis = Flapjack::RedisPool.new(:config => @redis_config, :size => 2)

        @logger.debug("New Pagerduty pikelet with the following options: #{@config.inspect}")

        @pagerduty_acks_started = nil
        super()
      end

      def stop
        @logger.info("stopping")
        @should_quit = true

        redis_uri = @redis_config[:path] ||
          "redis://#{@redis_config[:host] || '127.0.0.1'}:#{@redis_config[:port] || '6379'}/#{@redis_config[:db] || '0'}"
        shutdown_redis = EM::Hiredis.connect(redis_uri)
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
          event_json    = events[queue][1]

          begin
            event = Oj.load(event_json)
            @logger.debug("pagerduty notification event received: " + event.inspect)

            if 'shutdown'.eql?(event['notification_type'])
              @logger.debug("@should_quit: #{@should_quit}")
              next
            end

            alert = Flapjack::Data::Alert.new(event, :logger => @logger)
            @logger.debug("processing pagerduty notification service_key: #{alert.address}, entity: #{alert.entity}, " +
                          "check: '#{alert.check}', state: #{alert.state}, summary: #{alert.summary}")

            mydir = File.dirname(__FILE__)
            message_template_path = case
            when @config.has_key?('templates') && @config['templates']['alert.text']
              @config['templates']['alert.text']
            else
              mydir + "/pagerduty/alert.text.erb"
            end
            message_template = ERB.new(File.read(message_template_path), nil, '-')

            @alert = alert
            bnd    = binding

            begin
              message = message_template.result(bnd).chomp
            rescue => e
              @logger.error "Error while excuting the ERB for a pagerduty message, " +
                "ERB being executed: #{message_template_path}"
              raise
            end

            pagerduty_type = case alert.type
            when 'acknowledgement'
              'acknowledge'
            when 'problem'
              'trigger'
            when 'recovery'
              'resolve'
            when 'test'
              'trigger'
            end

            pagerduty_event = { 'service_key'  => alert.address,
                                'incident_key' => alert.event_id,
                                'event_type'   => pagerduty_type,
                                'description'  => message }

            send_pagerduty_event(pagerduty_event)
            alert.record_send_success!
          rescue => e
            @logger.error "Error generating or dispatching pagerduty message: #{e.class}: #{e.message}\n" +
              e.backtrace.join("\n")
            @logger.debug "Message that could not be processed: \n" + event_json
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
        unless status == 200
          raise "Error sending event to pagerduty: status: #{status.to_s} - #{response.inspect}" +
                " posted data: #{options[:body]}"
        end
        [status, response]
      end

      def find_pagerduty_acknowledgements
        @logger.debug("looking for acks in pagerduty for unack'd problems")

        unacknowledged_failing_checks = Flapjack::Data::EntityCheck.unacknowledged_failing(:redis => @redis)

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

          # FIXME: decide where the default acknowledgement period should reside and use it
          # everywhere ... a case for moving configuration into redis (from config file) perhaps?
          four_hours = 4 * 60 * 60
          Flapjack::Data::Event.create_acknowledgement(
            entity_name, check,
            :summary  => "Acknowledged on PagerDuty" + who_text,
            :duration => four_hours,
            :redis    => @redis)
        end

      end

      def pagerduty_acknowledged?(opts)
        subdomain   = opts['subdomain']
        username    = opts['username']
        password    = opts['password']
        check       = opts['check']

        unless subdomain && username && password && check
          @logger.warn("pagerduty_acknowledged?: Unable to look for acknowledgements on pagerduty" +
                       " as all of the following options are required:" +
                       " subdomain (#{subdomain}), username (#{username}), password (#{password}), check (#{check})")
          return nil
        end

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

