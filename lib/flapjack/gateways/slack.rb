#!/usr/bin/env ruby

require 'erb'

require 'flapjack/redis_proxy'
require 'flapjack/record_queue'
require 'flapjack/utility'
require 'flapjack/exceptions'

require 'flapjack/data/alert'

module Flapjack
  module Gateways
    class Slack

      include Flapjack::Utility

      attr_accessor :sent

      def initialize(opts = {})
        @lock = opts[:lock]
        @config = opts[:config]

        # TODO support for config reloading
        @queue = Flapjack::RecordQueue.new(@config['queue'] || 'slack_notifications',
                   Flapjack::Data::Alert)

        @sent = 0
      end

      def start
        Flapjack.logger.debug("new slack gateway pikelet with the following options: #{@config.inspect}")

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
        Flapjack.logger.debug "Woo, got an alert to send out: #{alert.inspect}"

        account_sid = @config['account_sid']
        endpoint    = @config['endpoint']
        icon_emoji  = @config['icon_emoji'] || ':ghost:'

        channel         = "##{alert.medium.address}"
        channel         = '#general' if (channel.size == 1)
        notification_id = alert.notification_id
        message_type    = alert.rollup ? 'rollup' : 'alert'

        slack_template_erb, slack_template =
          load_template(@config['templates'], message_type,
                        'text', File.join(File.dirname(__FILE__), 'slack'))

        @alert  = alert
        bnd     = binding

        message = nil
        begin
          message = slack_template_erb.result(bnd).chomp
        rescue => e
          Flapjack.logger.error 'Error while executing the ERB for a slack message: ' \
            "ERB being executed: #{slack_template}"
          raise
        end

        errors = []

        [
         [endpoint, 'Slack endpoint is missing'],
         [account_sid, 'Slack account_sid is missing']
        ].each do |val_err|

          next unless val_err.first.nil? || (val_err.first.respond_to?(:empty?) && val_err.first.empty?)
          errors << val_err.last
        end

        unless errors.empty?
          errors.each {|err| Flapjack.logger.error err }
          return
        end

        payload = Flapjack.dump_json(
          'channel'    => channel,
          'username'   => account_sid,
          'text'       => message,
          'icon_emoji' => icon_emoji
        )
        Flapjack.logger.debug "payload: #{payload.inspect}"

        uri = URI.parse(endpoint)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        request = Net::HTTP::Post.new(uri.request_uri)
        request.body = Flapjack.dump_json(:payload => payload)
        http_response = http.request(request)
        status   = http_response.code

        if (status >= 200) && (status <= 206)
          @sent += 1
          alert.record_send_success!
          Flapjack.logger.debug "Sent message via Slack, response status is #{status}, " +
            "notification_id: #{notification_id}"
        else
          Flapjack.logger.error "Failed to send message via Slack, response status is #{status}, " +
            "notification_id: #{notification_id}"
        end
      rescue => e
        Flapjack.logger.error "Error generating or delivering Slack message to #{alert.medium.address}: #{e.class}: #{e.message}"
        Flapjack.logger.error e.backtrace.join("\n")
        raise
      end

    end
  end
end

