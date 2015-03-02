#!/usr/bin/env ruby

require 'net/http'
require 'uri'
require 'uri/https'

require 'flapjack/redis_proxy'
require 'flapjack/record_queue'
require 'flapjack/exceptions'

require 'flapjack/data/alert'
require 'flapjack/data/check'
require 'flapjack/data/event'

module Flapjack

  module Gateways

    class Pagerduty

      class Notifier

        def initialize(opts = {})
          @lock = opts[:lock]
          @config = opts[:config]

          # TODO support for config reloading
          @queue = Flapjack::RecordQueue.new(@config['queue'] || 'pagerduty_notifications',
                     Flapjack::Data::Alert)

          Flapjack.logger.debug("New Pagerduty::Notifier pikelet with the following options: #{@config.inspect}")
        end

        def start
          until test_pagerduty_connection
            Flapjack.logger.error("Can't connect to the pagerduty API, retrying after 10 seconds")
            Kernel.sleep(10)
          end

          begin
            Zermelo.redis = Flapjack.redis

            loop do
              @lock.synchronize do
                @queue.foreach {|alert| handle_alert(alert) }
              end

              @queue.wait
            end
          ensure
            Flapjack.redis.quit
          end
        end

        def stop_type
          :exception
        end

        private

        def handle_alert(alert)
          check = alert.check

          address = alert.address

          Flapjack.logger.debug("processing pagerduty notification service_key: #{address}, " +
                        "check: '#{check.name}', state: #{alert.state}, summary: #{alert.summary}")

          pagerduty_dir = File.join(File.dirname(__FILE__), 'pagerduty')
          message_template_path = case
          when @config.has_key?('templates') && @config['templates']['alert.text']
            @config['templates']['alert.text']
          else
            File.join(pagerduty_dir, 'alert.text.erb')
          end

          message_template = ERB.new(File.read(message_template_path), nil, '-')

          @alert = alert
          bnd = binding

          msg = nil
          begin
            msg = message_template.result(bnd).chomp
          rescue => e
            Flapjack.logger.error "Error while executing the ERB for a pagerduty message, " +
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

          # quick fix, may not be true in all cases
          host_name, service_name = check.name.split(':', 2)

          # Setting the HOSTNAME and the SERVICE makes them visible in the Pagerduty UI
          send_pagerduty_event(:service_key  => address,
                               :incident_key => check.name,
                               :event_type   => pagerduty_type,
                               :description  => msg,
                               :details      => {'HOSTNAME' => host_name,
                                                 'SERVICE'  => service_name})

          Flapjack.logger.info "Sent alert successfully: #{alert.to_s}"
        rescue => e
          Flapjack.logger.error "Error generating or dispatching pagerduty message: #{e.class}: #{e.message}\n" +
            e.backtrace.join("\n")
          Flapjack.logger.debug "Alert that could not be processed: \n" + alert.inspect
        end

        def test_pagerduty_connection
          code, results = send_pagerduty_event(:service_key => '11111111111111111111111111111111',
                                               :incident_key => 'Flapjack is running a NOOP',
                                               :event_type => 'nop',
                                               :description => 'I love APIs with noops.')
          return true if '200'.eql?(code) && results['status'] =~ /success/i
          Flapjack.logger.error "Error: test_pagerduty_connection: API returned #{code.to_s} #{results.inspect}"
          false
        end

        # TODO trap Oj JSON errors
        def send_pagerduty_event(opts = {})
          event = { 'service_key'  => opts[:service_key],
                    'incident_key' => opts[:incident_key],
                    'event_type'   => opts[:event_type],
                    'description'  => opts[:description] }

          uri = URI::HTTPS.build(:host => 'events.pagerduty.com',
                                 :port => 443,
                                 :path => '/generic/2010-04-15/create_event.json')
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
          request = Net::HTTP::Post.new(uri.request_uri)
          request.body = Flapjack.dump_json(event)
          http_response = http.request(request)

          response = Flapjack.load_json(http_response.body)
          status   = http_response.code
          Flapjack.logger.debug "send_pagerduty_event got a return code of #{status} - #{response.inspect}"
          unless status.to_i == 200
            raise "Error sending event to pagerduty: status: #{status.to_s} - #{response.inspect}" +
                  " posted data: #{options[:body]}"
          end
          [status, response]
        end

      end

      class AckFinder

        SEM_PAGERDUTY_ACKS_RUNNING = 'sem_pagerduty_acks_running'

        def initialize(opts = {})
          @lock = opts[:lock]
          @config = opts[:config]

          Flapjack.logger.debug("New Pagerduty::AckFinder pikelet with the following options: #{@config.inspect}")

          if credentials = @config['credentials']
            @subdomain = credentials['subdomain']
            @username  = credentials['username']
            @password  = credentials['password']
          end

          # TODO: only clear this if there isn't another pagerduty gateway instance running
          # or better, include an instance ID in the semaphore key name
          Flapjack.redis.del(SEM_PAGERDUTY_ACKS_RUNNING)
        end

        def start
          loop do
            @lock.synchronize do
              # ensure we're the only instance of the pagerduty acknowledgement check running (with a naive
              # timeout of five minutes to guard against stale locks caused by crashing code) either in this
              # process or in other processes
              if Flapjack.redis.setnx(SEM_PAGERDUTY_ACKS_RUNNING, 'true') == 0
                Flapjack.logger.debug("skipping looking for acks in pagerduty as this is already happening")
              else
                Flapjack.redis.expire(SEM_PAGERDUTY_ACKS_RUNNING, 300)
                find_pagerduty_acknowledgements
                Flapjack.redis.del(SEM_PAGERDUTY_ACKS_RUNNING)
              end
            end

            Kernel.sleep 10
          end
        end

        def stop_type
          :exception
        end

        def find_pagerduty_acknowledgements
          Flapjack.logger.debug("looking for acks in pagerduty for unack'd problems")

          state_ids_by_check_id = Flapjack::Data::Check.associated_ids_for(:state)

          failing_check_ids = Flapjack::Data::State.
            intersect(:id => state_ids_by_check_id.values,
                      :condition => Flapjack::Data::Condition.unhealthy.keys).
            associated_ids_for(:check).values

          time = Time.now

          # there are probably more efficient ways to do this calculation
          unacked_failing_checks = Flapjack::Data::Check.
            intersect(:id => failing_check_ids).select do |check|

            check.scheduled_maintenance_at(time).nil? &&
              check.unscheduled_maintenance_at(time).nil?
          end

          Flapjack.logger.debug "found unacknowledged failing checks as follows: " +
            unacked_failing_checks.map(&:name).join(', ')

          # so credentials_by_check are all the unacknowledged problems in flapjack as check:credentials
          credentials_by_check = Flapjack::Data::Check.
            pagerduty_credentials_for(unacked_failing_checks.map(&:id))

          not_empty_credentials_by_check = credentials_by_check.select do |check|
            !check.empty?
          end

          pg_acks = pagerduty_acknowledgements
          incident_keys = pg_acks['incidents']['incident_key']
          
          not_empty_credentials_by_check.each_pair do |check, credentials|
            options = credentials.first.merge('check' => check.name)
            check2 = opts['check']

            # if check2 is in the pg_acks incidents, make a flapjack acknowledgement
            if incident_keys[check2].nil?
              next
            end

        # returns the pagerduty acknowloedgements
        def pagerduty_acknowledgements
          if @username.blank? || @password.blank?
            Flapjack.logger.warn("pagerduty_acknowledgements?: Unable to look for acknowledgements on pagerduty" +
                         " as all of the following options are required:" +
                         " username (#{@username}), password (#{@password})")
            return nil
          end

          t = Time.now.utc

          query = {'fields'       => 'incident_number,status,last_status_change_by',
                   'since'        => (t - (60*60*24*7)).iso8601, # the last week
                   'until'        => (t + (60*60*24)).iso8601,   # 1 day in the future
                   'status'       => 'acknowledged'}

          uri = URI::HTTPS.build(:host => "pagerduty.com",
                                 :path => '/api/v1/incidents',
                                 :port => 443,
                                 :query => URI.encode_www_form(query))
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
          request = Net::HTTP::Get.new(uri.request_uri)
          request.basic_auth(@username, @password)

          Flapjack.logger.debug("pagerduty_acknowledgements: request to #{uri.request_uri}")
          Flapjack.logger.debug("pagerduty_acknowledgements: query: #{query.inspect}")
          Flapjack.logger.debug("pagerduty_acknowledgements: auth: #{@username}, #{@password}")

          http_response = http.request(request)

          begin
            response = Flapjack.load_json(http_response.body)
          rescue Oj::Error
            Flapjack.logger.error("failed to parse json from a post to #{url} ... response headers and body follows...")
          end
          Flapjack.logger.debug(http_response.inspect)
          status   = http_response.code

          Flapjack.logger.debug("pagerduty_acknowledgements: decoded response as: #{response.inspect}")
          if response.nil?
            Flapjack.logger.error('no valid response received from pagerduty!')
            return nil
          end

          return nil if response['incidents'].empty?

          response
        end
          
      end
    end
  end
end

