#!/usr/bin/env ruby

require 'eventmachine'
# the redis/synchrony gems need to be required in this particular order, see
# the redis-rb README for details
require 'hiredis'
require 'em-synchrony'
require 'em-synchrony/em-http'
require 'redis/connection/synchrony'
require 'redis'

require 'yajl/json_gem'

require 'flapjack/data/entity_check'
require 'flapjack/data/global'
require 'flapjack/pikelet'

module Flapjack

  class Pagerduty

    include Flapjack::Pikelet

    PAGERDUTY_EVENTS_API_URL   = 'https://events.pagerduty.com/generic/2010-04-15/create_event.json'
    SEM_PAGERDUTY_ACKS_RUNNING = 'sem_pagerduty_acks_running'

    def setup
      @redis = build_redis_connection_pool
      logger.debug("New Pagerduty pikelet with the following options: #{@config.inspect}")

      @pagerduty_acks_started = nil
    end

    def add_shutdown_event(opts = {})
      return unless redis = opts[:redis]
      redis.rpush(@config['queue'], JSON.generate('notification_type' => 'shutdown'))
    end

    def main
      setup

      logger.debug("pagerduty gateway - commencing main method")
      raise "Can't connect to the pagerduty API" unless test_pagerduty_connection

      # TODO: only clear this if there isn't another pagerduty gateway instance running
      # or better, include an instance ID in the semaphore key name
      @redis.del(SEM_PAGERDUTY_ACKS_RUNNING)

      acknowledgement_timer = EM::Synchrony.add_periodic_timer(10) do
        @redis_timer ||= build_redis_connection_pool
        find_pagerduty_acknowledgements_if_safe
      end

      queue = @config['queue']
      events = {}

      until should_quit?
        logger.debug("pagerduty gateway is going into blpop mode on #{queue}")
        events[queue] = @redis.blpop(queue, 0)
        event         = Yajl::Parser.parse(events[queue][1])
        type          = event['notification_type']
        logger.debug("pagerduty notification event popped off the queue: " + event.inspect)
        unless 'shutdown'.eql?(type)
          event_id      = event['event_id']
          entity, check = event_id.split(':')
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

      @redis.empty! if @redis
      @redis_timer.empty! if @redis_timer
    end

    # considering this as part of the public API -- exposes it for testing.
    def find_pagerduty_acknowledgements_if_safe

      # ensure we're the only instance of the pagerduty acknowledgement check running (with a naive
      # timeout of five minutes to guard against stale locks caused by crashing code) either in this
      # process or in other processes
      if (@pagerduty_acks_started and @pagerduty_acks_started > (Time.now.to_i - 300)) or
          @redis_timer.get(SEM_PAGERDUTY_ACKS_RUNNING) == 'true'
        logger.debug("skipping looking for acks in pagerduty as this is already happening")
        return
      end

      @pagerduty_acks_started = Time.now.to_i
      @redis_timer.set(SEM_PAGERDUTY_ACKS_RUNNING, 'true')
      @redis_timer.expire(SEM_PAGERDUTY_ACKS_RUNNING, 300)

      find_pagerduty_acknowledgements

      @redis_timer.del(SEM_PAGERDUTY_ACKS_RUNNING)
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
      logger.error "Error: test_pagerduty_connection: API returned #{code.to_s} #{results.inspect}"
      false
    end

    def send_pagerduty_event(event)
      options  = { :body => Yajl::Encoder.encode(event) }
      http = EM::HttpRequest.new(PAGERDUTY_EVENTS_API_URL).post(options)
      response = Yajl::Parser.parse(http.response)
      status   = http.response_header.status
      logger.debug "send_pagerduty_event got a return code of #{status.to_s} - #{response.inspect}"
      [status, response]
    end

    def find_pagerduty_acknowledgements

      logger.debug("looking for acks in pagerduty for unack'd problems")

      unacknowledged_failing_checks = Flapjack::Data::Global.unacknowledged_failing_checks(:redis => @redis_timer)

      @logger.debug "found unacknowledged failing checks as follows: " + unacknowledged_failing_checks.join(', ')

      unacknowledged_failing_checks.each do |entity_check|
        pagerduty_credentials = entity_check.pagerduty_credentials(:redis => @redis_timer)
        check = entity_check.check

        if pagerduty_credentials.empty?
          @logger.debug("No pagerduty credentials found for #{entity_check.entity_name}:#{check}, skipping")
          next
        end

        # FIXME: try each set of credentials until one works (may have stale contacts turning up)
        options = pagerduty_credentials.first.merge('check' => check)

        acknowledged = pagerduty_acknowledged?(options)
        if acknowledged.nil?
          @logger.debug "#{check} is not acknowledged in pagerduty, skipping"
          next
        end

        pg_acknowledged_by = acknowledged[:pg_acknowledged_by]
        @logger.debug "#{check} is acknowledged in pagerduty, creating flapjack acknowledgement... "
        who_text = ""
        if !pg_acknowledged_by.nil? && !pg_acknowledged_by['name'].nil?
          who_text = " by #{pg_acknowledged_by['name']}"
        end
        entity_check.create_acknowledgement('summary' => "Acknowledged on PagerDuty" + who_text)
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

      http = EM::HttpRequest.new(url).get(options)
      # DEBUG flapjack-pagerduty: pagerduty_acknowledged?: decoded response as:
      # {"incidents"=>[{"incident_number"=>40, "status"=>"acknowledged",
      # "last_status_change_by"=>{"id"=>"PO1NWPS", "name"=>"Jesse Reynolds",
      # "email"=>"jesse@bulletproof.net",
      # "html_url"=>"http://bltprf.pagerduty.com/users/PO1NWPS"}}], "limit"=>100, "offset"=>0,
      # "total"=>1}
      begin
        response = Yajl::Parser.parse(http.response)
      rescue Yajl::ParseError
        @logger.error("failed to parse json from a post to #{url} ... response headers and body follows...")
        @logger.error(http.response_header.inspect)
        @logger.error(http.response)
        return nil
      end
      status   = http.response_header.status

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

