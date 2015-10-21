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

    class PagerDuty

      # FIXME trap JSON errors
      def self.send_pagerduty_event(opts = {})
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
        request = Net::HTTP::Post.new(uri.request_uri,
          {'Content-type' =>'application/json'})
        request.body = Flapjack.dump_json(event)
        http_response = http.request(request)
        status   = http_response.code

        response = nil
        begin
          response = Flapjack.load_json(http_response.body)
        rescue JSON::JSONError
          Flapjack.logger.error("failed to parse json from a post to #{uri.request_uri} ... response headers and body follows...")
        end

        Flapjack.logger.debug "send_pagerduty_event got a return code of #{status} - #{response.inspect}"
        unless status.to_i == 200
          raise "Error sending event to PagerDuty: status: #{status.to_s} - #{response.inspect}" +
                " posted data: #{options[:body]}"
        end
        [status, response]
      end

      def self.test_pagerduty_connection
        code, results = send_pagerduty_event(:service_key => '11111111111111111111111111111111',
                                             :incident_key => 'Flapjack is running a NOOP',
                                             :event_type => 'nop',
                                             :description => 'I love APIs with noops.')
        return true if '200'.eql?(code) && results['status'] =~ /success/i
        Flapjack.logger.error "Error: test_pagerduty_connection: API returned #{code.to_s} #{results.inspect}"
        false
      end

      class Notifier

        include Flapjack::Utility

        def initialize(opts = {})
          @lock = opts[:lock]
          @config = opts[:config]

          # TODO support for config reloading
          @queue = Flapjack::RecordQueue.new(@config['queue'] || 'pagerduty_notifications',
                     Flapjack::Data::Alert)

          Flapjack.logger.debug("New PagerDuty::Notifier pikelet with the following options: #{@config.inspect}")
        end

        def start
          until Flapjack::Gateways::PagerDuty.test_pagerduty_connection
            Flapjack.logger.error("Can't connect to the PagerDuty API, retrying after 10 seconds")
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

          Flapjack.logger.debug("processing PagerDuty notification service_key: #{address}, " +
                        "check: '#{check.name}', state: #{alert.state}, summary: #{alert.summary}")

          message_template_erb, message_template =
            load_template(@config['templates'], 'alert',
                          'text', File.join(File.dirname(__FILE__), 'pager_duty'))

          @alert = alert
          bnd = binding

          msg = nil
          begin
            msg = message_template_erb.result(bnd).chomp
          rescue => e
            Flapjack.logger.error "Error while executing the ERB for a PagerDuty message, " +
              "ERB being executed: #{message_template}"
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

          # Setting the HOSTNAME and the SERVICE makes them visible in the PagerDuty UI
          Flapjack::Gateways::PagerDuty.send_pagerduty_event(
            :service_key  => address,
            :incident_key => check.name,
            :event_type   => pagerduty_type,
            :description  => msg,
            :details      => {'HOSTNAME' => host_name,
                               'SERVICE' => service_name}
          )

          Flapjack.logger.info "Sent alert successfully: #{alert.to_s}"
        rescue => e
          Flapjack.logger.error "Error generating or dispatching PagerDuty message: #{e.class}: #{e.message}\n" +
            e.backtrace.join("\n")
          Flapjack.logger.debug "Alert that could not be processed: \n" + alert.inspect
        end

      end

      class AckFinder
        SEM_PAGERDUTY_ACKS_RUNNING = 'sem_pagerduty_acks_running'
        SEM_PAGERDUTY_ACKS_RUNNING_TIMEOUT = 3600

        def initialize(opts = {})
          @lock = opts[:lock]
          @config = opts[:config]

          @initial = true

          Flapjack.logger.debug("New PagerDuty::AckFinder pikelet with the following options: #{@config.inspect}")

          # TODO: only clear this if there isn't another PagerDuty gateway instance running
          # or better, include an instance ID in the semaphore key name
          Flapjack.redis.del(SEM_PAGERDUTY_ACKS_RUNNING)
        end

        def start
          until Flapjack::Gateways::PagerDuty.test_pagerduty_connection
            Flapjack.logger.error("Can't connect to the PagerDuty API, retrying after 10 seconds")
            Kernel.sleep(10)
          end

          begin
            Zermelo.redis = Flapjack.redis

            loop do
              @lock.synchronize do
                # ensure we're the only instance of the PagerDuty acknowledgement check running (with a naive
                # timeout of one hour to guard against stale locks caused by crashing code) either in this
                # process or in other processes
                if Flapjack.redis.setnx(SEM_PAGERDUTY_ACKS_RUNNING, 'true') == 0
                  Flapjack.logger.debug("skipping looking for acks in PagerDuty as this is already happening")
                else
                  Flapjack.redis.expire(SEM_PAGERDUTY_ACKS_RUNNING, SEM_PAGERDUTY_ACKS_RUNNING_TIMEOUT)
                  find_pagerduty_acknowledgements
                  Flapjack.redis.del(SEM_PAGERDUTY_ACKS_RUNNING)
                end

                Kernel.sleep 10
              end
            end
          ensure
            Flapjack.redis.quit
          end
        end

        def stop_type
          :exception
        end

        def find_pagerduty_acknowledgements
          Flapjack.logger.debug("looking for acks in PagerDuty for unack'd problems")

          time = Time.now

          unacked_failing_checks = []

          Flapjack::Data::Check.lock(Flapjack::Data::ScheduledMaintenance,
            Flapjack::Data::UnscheduledMaintenance) do

            unacked_failing_checks = Flapjack::Data::Check.
              intersect(:failing => true).reject do |check|

                check.in_unscheduled_maintenance?(time) ||
                  check.in_scheduled_maintenance?(time)
            end
          end

          if unacked_failing_checks.empty?
            Flapjack.logger.debug "found no unacknowledged failing checks"
            return
          end

          Flapjack.logger.debug "found unacknowledged failing checks as follows: " +
            unacked_failing_checks.map(&:name).join(', ')

          check_ids_by_medium(unacked_failing_checks.map(&:id), :time => time).each_pair do |medium, check_ids|
            next if check_ids.empty?
            checks = unacked_failing_checks.select {|c| check_ids.include?(c.id)}
            next if checks.empty?

            pagerduty_acknowledgements(time, medium.pagerduty_subdomain,
                                       medium.pagerduty_token,
                                       checks.map(&:name)).each do |incident|

              inc_key = incident['incident_key']

              pg_acknowledged_by = incident['last_status_change_by']
              Flapjack.logger.info "#{inc_key} is acknowledged in PagerDuty, creating flapjack acknowledgement... "

              who_text = ""

              if !pg_acknowledged_by.nil? && !pg_acknowledged_by['name'].nil?
                who_text = " by #{pg_acknowledged_by['name']}"
              end

              # default to 4 hours if no duration set in the medium
              ack_duration = medium.pagerduty_ack_duration || (4 * 60 * 60)

              Flapjack::Data::Event.create_acknowledgements(
                @config['processor_queue'] || 'events',
                [checks.detect {|c| c.name == inc_key}],
                :summary  => "Acknowledged on PagerDuty" + who_text,
                :duration => ack_duration)
            end
          end
        end

        def check_ids_by_medium(filter_check_ids, opts = {})
          time = opts[:time]

          Flapjack::Data::Medium.lock(Flapjack::Data::Check, Flapjack::Data::Rule) do

            media = Flapjack::Data::Medium.intersect(:transport => 'pagerduty')

            already_acking_ids = []

            media.all.each_with_object({}) do |medium, memo|
              init_scope = Flapjack::Data::Check.intersect(:id => filter_check_ids)
              ch_ids = medium.checks(:initial_scope => init_scope, :time => time).ids

              to_ack_ids = (ch_ids & filter_check_ids) - already_acking_ids
              already_acking_ids.push(*to_ack_ids)
              memo[medium] = to_ack_ids
            end
          end
        end

        # returns any PagerDuty acknowledgements for the named checks
        def pagerduty_acknowledgements(time, subdomain, token, check_names)
          if subdomain.blank? || token.blank?
            Flapjack.logger.warn("pagerduty_acknowledgements?: Unable to look for acknowledgements on PagerDuty" \
             " as the following options are required: subdomain (#{subdomain}), token (#{token})")
            return
          end

          t = time.utc

          # handle paginated results
          cumulative_incidents = []

          offset = 0
          requesting = true

          while requesting do
            response = pagerduty_acknowledgements_request(t, subdomain, token, 100, offset)

            if response.nil?
              cumulative_incidents = []
              requesting = false
            else
              cumulative_incidents += response['incidents'].select do |incident|
                check_names.include?(incident['incident_key'])
              end

              offset = response['offset'] + response['incidents'].size

              requesting = (offset < response['total'])
            end
          end

          @initial = false

          cumulative_incidents
        end

        def pagerduty_acknowledgements_request(base_time, subdomain, token, limit, offset)
          since_offset, until_offset = if @initial
            # the last week -> one hour in the future
            [(60 * 60 * 24 * 7), (60 * 60)]
          else
            # the last 15 minutes -> one hour in the future
            [(60 * 15), (60 * 60)]
          end

          query = {'fields'       => 'incident_key,incident_number,last_status_change_by',
                   'since'        => (base_time - since_offset).iso8601,
                   'until'        => (base_time + until_offset).iso8601,
                   'status'       => 'acknowledged'}

          if (limit != 100) || (offset != 0)
            query.update(:limit => limit, :offset => offset)
          end

          uri = URI::HTTPS.build(:host => "#{subdomain}.pagerduty.com",
                                 :path => '/api/v1/incidents',
                                 :port => 443,
                                 :query => URI.encode_www_form(query))

          request = Net::HTTP::Get.new(uri.request_uri,
            {'Content-type'  => 'application/json',
             'Authorization' => "Token token=#{token}"})

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER

          Flapjack.logger.debug("pagerduty_acknowledgements: request to #{uri.request_uri}")
          Flapjack.logger.debug("pagerduty_acknowledgements: query: #{query.inspect}")
          Flapjack.logger.debug("pagerduty_acknowledgements: auth: #{token}")

          http_response = http.request(request)
          Flapjack.logger.debug(http_response.inspect)

          response = nil
          begin
            response = Flapjack.load_json(http_response.body)
          rescue JSON::JSONError
            Flapjack.logger.error("failed to parse json from a post to #{url} ... response headers and body follows...")
          end

          Flapjack.logger.debug("pagerduty_acknowledgements: decoded response as: #{response.inspect}")
          if response.nil? || !response.has_key?('incidents') || !response['incidents'].is_a?(Array)
            Flapjack.logger.error('no valid response received from PagerDuty!')
            return
          end

          response
        end

      end
    end
  end
end
