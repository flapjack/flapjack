#!/usr/bin/env ruby

require 'oj'

require 'net/http'
require 'uri'
require 'uri/http'

require 'flapjack/data/entity_check'
require 'flapjack/data/global'

module Flapjack

  module Gateways

    class Pagerduty

      class Notifier

        include MonitorMixin

        def initialize(opts = {})
          @config = opts[:config]
          @logger = opts[:logger]
          @redis_config = opts[:redis_config] || {}

          @redis = Redis.new(@redis_config.merge(:driver => :hiredis))

          @notifications_queue = @config['queue'] || 'pagerduty_notifications'

          mon_initialize

          @logger.debug("New Pagerduty::Notifier pikelet with the following options: #{@config.inspect}")
        end

        def start
          @logger.info("starting")
          until test_pagerduty_connection
            @logger.error("Can't connect to the pagerduty API, retrying after 10 seconds")
            Kernel.sleep(10)
          end

          loop do
            synchronize do
              Flapjack::Data::Message.foreach_on_queue(@notifications_queue, :redis => @redis) {
                handle_message(message)
              }
            end

            Flapjack::Data::Message.wait_for_queue(@notifications_queue)
          end

        rescue Flapjack::PikeletStop => fps
          @logger.info "stopping jabber notifier"
        end

        def stop(thread)
          synchronize do
            thread.raise Flapjack::PikeletStop.new
          end
        end

        private

        def handle_message(message)
          event_id      = message['event_id']
          entity, check = event_id.split(':', 2)
          state         = message['state']
          summary       = message['summary']
          address       = message['address']

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
          uri = URI::HTTP.build(:host => 'https://events.pagerduty.com',
                                :path => '/generic/2010-04-15/create_event.json')
          http = Net::HTTP.new(uri.host, uri.port)
          request = Net::HTTP::Post.new(uri.request_uri)
          request.body = Oj.dump(event)
          http_response = http.request(request)

          response = Oj.load(http_response.body)
          status   = http_response_header.code
          @logger.debug "send_pagerduty_event got a return code of #{status.to_s} - #{response.inspect}"
          [status, response]
        end

      end

      class AckFinder

        SEM_PAGERDUTY_ACKS_RUNNING = 'sem_pagerduty_acks_running'

        def initialize(opts = {})
          @config = opts[:config]
          @logger = opts[:logger]
          @redis_config = opts[:redis_config] || {}

          @redis = Redis.new(@redis_config.merge(:driver => :hiredis))

          @logger.debug("New Pagerduty::AckFinder pikelet with the following options: #{@config.inspect}")

          # TODO: only clear this if there isn't another pagerduty gateway instance running
          # or better, include an instance ID in the semaphore key name
          @redis.del(SEM_PAGERDUTY_ACKS_RUNNING)
        end

        def start
          loop do
            synchronized do
              # ensure we're the only instance of the pagerduty acknowledgement check running (with a naive
              # timeout of five minutes to guard against stale locks caused by crashing code) either in this
              # process or in other processes
              if @redis.setnx(SEM_PAGERDUTY_ACKS_RUNNING, 'true') == 0
                @logger.debug("skipping looking for acks in pagerduty as this is already happening")
              else
                @redis.expire(SEM_PAGERDUTY_ACKS_RUNNING, 300)
                find_pagerduty_acknowledgements
                @redis.del(SEM_PAGERDUTY_ACKS_RUNNING)
              end
            end

            Kernel.sleep 10
          end

        rescue Flapjack::PikeletStop
          @logger.info "ending pagerduty ackfinder"
        end

        def stop(thread)
          synchronized do
            thread.raise Flapjack::PikeletStop.new
          end
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
              @config['processor_queue'] || 'events',
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

          query = {'fields'       => 'incident_number,status,last_status_change_by',
                   'since'        => (t - (60*60*24*7)).iso8601, # the last week
                   'until'        => (t + (60*60*24)).iso8601,   # 1 day in the future
                   'incident_key' => check,
                   'status'       => 'acknowledged'}

          uri = URI::HTTP.build(:host => 'https://' + subdomain + '.pagerduty.com',
                                :path => '/api/v1/incidents',
                                :query => URI.encode_www_form(query))
          http = Net::HTTP.new(uri.host, uri.port)
          request = Net::HTTP::Get.new(uri.request_uri)
          request.basic_auth(username, password)

          @logger.debug("pagerduty_acknowledged?: request to #{uri.request_uri}")
          @logger.debug("pagerduty_acknowledged?: query: #{query.inspect}")
          @logger.debug("pagerduty_acknowledged?: auth: #{username}, #{password}")

          http_response = http.request(request)

          begin
            response = Oj.load(http_response.body)
          rescue Oj::Error
            @logger.error("failed to parse json from a post to #{url} ... response headers and body follows...")
            return nil
          end
          @logger.debug(http_response.inspect)
          status   = http_response.code

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

end

