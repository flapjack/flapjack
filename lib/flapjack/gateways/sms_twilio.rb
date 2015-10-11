#!/usr/bin/env ruby

require 'net/http'
require 'uri'
require 'uri/https'

require 'active_support/inflector'

require 'flapjack/redis_proxy'
require 'flapjack/record_queue'
require 'flapjack/utility'
require 'flapjack/exceptions'

require 'flapjack/data/alert'
require 'flapjack/data/check'

module Flapjack
  module Gateways
    class SmsTwilio

      # curl -X POST 'https://api.twilio.com/2010-04-01/Accounts/[AccountSid]/Messages.json' \
      # --data-urlencode 'To=+61414123456'  \
      # --data-urlencode 'From=+61414123456'  \
      # --data-urlencode 'Body=Sausage' \
      # -u [AccountSid]:[AuthToken]

      TWILIO_DEFAULT_HOST = 'api.twilio.com'

      attr_accessor :sent

      include Flapjack::Utility

      def initialize(opts = {})
        @lock = opts[:lock]

        @config = opts[:config]

        # TODO support for config reloading
        @queue = Flapjack::RecordQueue.new(@config['queue'] || 'sms_twilio_notifications',
                   Flapjack::Data::Alert)

        @sent = 0

        Flapjack.logger.debug("new sms_twilio gateway pikelet with the following options: #{@config.inspect}")
      end

      def start
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
        account_sid = @config["account_sid"]
        auth_token = @config["auth_token"]
        from = @config["from"]

        endpoint_host = @config["endpoint_host"] || TWILIO_DEFAULT_HOST
        endpoint_path = @config["endpoint_path"] || "/2010-04-01/Accounts/#{account_sid}/Messages.json"

        address = alert.medium.address
        notification_id = alert.id
        message_type = alert.rollup ? 'rollup' : 'alert'

        sms_dir = File.join(File.dirname(__FILE__), 'sms_twilio')
        sms_template_erb, sms_template =
          load_template(@config['templates'], message_type, 'text', sms_dir)

        @alert = alert
        bnd = binding

        begin
          message = sms_template_erb.result(bnd).chomp
        rescue => e
          Flapjack.logger.error "Error while executing the ERB for an sms: " +
            "ERB being executed: #{sms_template}"
          raise
        end

        if @config.nil? || (@config.respond_to?(:empty?) && @config.empty?)
          Flapjack.logger.error "sms twilio config is missing"
          return
        end

        errors = []

        [[account_sid, "Twilio account_sid is missing"],
         [auth_token, "Twilio auth_token is missing"],
         [from, "SMS from address is missing"],
         [address, "SMS address is missing"],
         [notification_id, "Notification id is missing"]].each do |val_err|

          next unless val_err.first.nil? || (val_err.first.respond_to?(:empty?) && val_err.first.empty?)
          errors << val_err.last
        end

        unless errors.empty?
          errors.each {|err| Flapjack.logger.error err }
          return
        end

        body_data = {
          'To'   => address,
          'From' => from,
          'Body' => truncate(message, 159)
        }

        Flapjack.logger.debug "body_data: #{body_data.inspect}"
        Flapjack.logger.debug "authorization: [#{account_sid}, #{auth_token[0..2]}...#{auth_token[-3..-1]}]"

        req = Net::HTTP::Post.new(endpoint_path)
        req.set_form_data(body_data)
        req['Authorization'] = [account_sid, auth_token]

        http_response = Net::HTTP.start(endpoint_host, 443, :use_ssl => true) do |http|
          http.request(req)
        end

        Flapjack.logger.debug "server response: #{http_response.inspect}"

        status = http_response.code

        if (status.to_i >= 200) && (status.to_i <= 206)
          @sent += 1
          Flapjack.logger.info "Sent SMS via Twilio, response status is #{status}, " +
            "alert id: #{alert.id}"
        else
          Flapjack.logger.error "Failed to send SMS via Twilio, response status is #{status}, " +
            "alert id: #{alert.id}"
        end
      rescue => e
        Flapjack.logger.error "Error generating or delivering twilio sms to #{alert.medium.address}: #{e.class}: #{e.message}"
        Flapjack.logger.error e.backtrace.join("\n")
        raise
      end

    end
  end
end

