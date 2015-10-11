#!/usr/bin/env ruby

require 'erb'

require 'nexmo'

require 'flapjack/redis_proxy'
require 'flapjack/record_queue'
require 'flapjack/utility'
require 'flapjack/exceptions'

require 'flapjack/data/alert'

module Flapjack
  module Gateways
    class SmsNexmo

      include Flapjack::Utility

      attr_accessor :sent

      def initialize(opts = {})
        @lock = opts[:lock]
        @config = opts[:config]

        # TODO support for config reloading
        @queue = Flapjack::RecordQueue.new(@config['queue'] || 'sms_nexmo_notifications',
                   Flapjack::Data::Alert)

        @sent = 0
      end

      def start
        Flapjack.logger.debug("new sms_nexmo gateway pikelet with the following options: #{@config.inspect}")

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

        api_key = @config["api_key"]
        secret = @config["secret"]
        from = @config["from"]

        address = alert.medium.address
        message_type    = alert.rollup ? 'rollup' : 'alert'

        sms_dir = File.join(File.dirname(__FILE__), 'sms_nexmo')
        sms_nexmo_template_erb, sms_nexmo_template =
          load_template(@config['templates'], message_type, 'text', sms_dir)

        @alert  = alert
        bnd     = binding

        begin
          message = sms_nexmo_template_erb.result(bnd).chomp
        rescue => e
          Flapjack.logger.error "Error while executing the ERB for a Nexmo SMS: " +
            "ERB being executed: #{sms_nexmo_template}"
          raise
        end

        if @config.nil? || (@config.respond_to?(:empty?) && @config.empty?)
          Flapjack.logger.error "Nexmo SMS config is missing"
          return
        end

        errors = []

        safe_message = (message.length > 159) ?
                        message[0..158].gsub(/...$/, '...') : message,

        [[api_key, "Nexmo api_key is missing"],
         [secret, "Nexmo auth_token is missing"],
         [from,  "Nexmo from address is missing"],
         [address,  "Nexmo address is missing"]].each do |val_err|

          next unless val_err.first.nil? || (val_err.first.respond_to?(:empty?) && val_err.first.empty?)
          errors << val_err.last
        end

        unless errors.empty?
          errors.each {|err| Flapjack.logger.error err }
          return
        end

        begin
          nexmo = Nexmo::Client.new(:key => api_key, :secret => secret)
          nexmo.send_message(:from => from, :to => address, :text => safe_message)
          @sent += 1
        rescue => e
          Flapjack.logger.error "Error sending SMS via Nexmo: #{e.message}"
        end
      rescue => e
        Flapjack.logger.error "Error generating or delivering Nexmo SMS message to #{alert.medium.address}: #{e.class}: #{e.message}"
        Flapjack.logger.error e.backtrace.join("\n")
        raise
      end

    end
  end
end
