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
    class SmsMessagenet

      MESSAGENET_DEFAULT_HOST = 'www.messagenet.com.au'
      MESSAGENET_DEFAULT_PATH = '/dotnet/Lodge.asmx/LodgeSMSMessage'

      attr_accessor :sent

      include Flapjack::Utility

      def initialize(opts = {})
        @lock = opts[:lock]

        @config = opts[:config]

        # TODO support for config reloading
        @queue = Flapjack::RecordQueue.new(@config['queue'] || 'sms_notifications',
                   Flapjack::Data::Alert)

        @sent = 0

        Flapjack.logger.debug("new sms gateway pikelet with the following options: #{@config.inspect}")
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
        endpoint_host = @config["endpoint_host"] || MESSAGENET_DEFAULT_HOST
        endpoint_path = @config["endpoint_path"] || MESSAGENET_DEFAULT_PATH
        username = @config["username"]
        password = @config["password"]

        address = alert.medium.address
        notification_id = alert.id
        message_type = alert.rollup ? 'rollup' : 'alert'

        sms_dir = File.join(File.dirname(__FILE__), 'sms_messagenet')
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
          Flapjack.logger.error "Messagenet config is missing"
          return
        end

        errors = []

        safe_message = truncate(message, 156)

        [[username, "Messagenet username is missing"],
         [password, "Messagenet password is missing"],
         [address, "SMS address is missing"],
         [notification_id, "Notification id is missing"]].each do |val_err|

          next unless val_err.first.nil? || (val_err.first.respond_to?(:empty?) && val_err.first.empty?)
          errors << val_err.last
        end

        unless errors.empty?
          errors.each {|err| Flapjack.logger.error err }
          return
        end

        query = {'Username' => username,
                 'Pwd' => password,
                 'PhoneNumber' => address,
                 'PhoneMessage' => safe_message}

        # TODO ensure we're not getting a cached response from a proxy or similar,
        # use appropriate headers etc.
        uri = URI::HTTPS.build(:host => endpoint_host,
                               :path => endpoint_path,
                               :port => 443,
                               :query => URI.encode_www_form(query))

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        request = Net::HTTP::Get.new(uri.request_uri)

        http_response = http.request(request)

        Flapjack.logger.debug "server response: #{http_response.inspect}"

        status = http_response.code

        if (status.to_i >= 200) && (status.to_i <= 206)
          @sent += 1
          Flapjack.logger.info "Sent SMS via Messagenet, response status is #{status}, " +
            "alert id: #{alert.id}"
        else
          Flapjack.logger.error "Failed to send SMS via Messagenet, response status is #{status}, " +
            "alert id: #{alert.id}"
        end
      rescue => e
        Flapjack.logger.error "Error generating or delivering sms to #{alert.medium.address}: #{e.class}: #{e.message}"
        Flapjack.logger.error e.backtrace.join("\n")
        raise
      end

    end
  end
end

