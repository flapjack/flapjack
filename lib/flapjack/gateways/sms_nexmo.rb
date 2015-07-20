#!/usr/bin/env ruby

require 'em-synchrony'
require 'em-synchrony/em-http'
require 'active_support/inflector'

require 'flapjack/redis_pool'

require 'flapjack/data/alert'
require 'flapjack/utility'

require 'nexmo'

module Flapjack
  module Gateways
    class SmsNexmo

      include Flapjack::Utility

      def initialize(opts = {})
        @config = opts[:config]
        @logger = opts[:logger]
        @redis_config = opts[:redis_config] || {}
        @redis = Flapjack::RedisPool.new(:config => @redis_config, :size => 1, :logger => @logger)

        @logger.info("starting")
        @logger.debug("new sms_nexmo gateway pikelet with the following options: #{@config.inspect}")

        @sent = 0
      end

      def stop
        @logger.info("stopping")
        @should_quit = true

        redis_uri = @redis_config[:path] ||
          "redis://#{@redis_config[:host] || '127.0.0.1'}:#{@redis_config[:port] || '6379'}/#{@redis_config[:db] || '0'}"
        shutdown_redis = EM::Hiredis.connect(redis_uri)
        shutdown_redis.rpush(@config['queue'], Flapjack.dump_json('notification_type' => 'shutdown'))
      end

      def start
        queue = @config['queue']

        until @should_quit
          begin
            @logger.debug("sms_nexmo gateway is going into blpop mode on #{queue}")
            alert = Flapjack::Data::Alert.next(queue, :redis => @redis, :logger => @logger)
            deliver(alert) unless alert.nil?
          rescue => e
            @logger.error "Error generating or dispatching SMS Nexmo message: #{e.class}: #{e.message}\n" +
              e.backtrace.join("\n")
          end
        end
      end

      def deliver(alert)
        api_key = @config["api_key"]
        secret = @config["secret"]
        from = @config["from"]

        address         = alert.address
        notification_id = alert.notification_id
        message_type    = alert.rollup ? 'rollup' : 'alert'

        sms_template_erb, sms_template =
          load_template(@config['templates'], message_type, 'text',
                        File.join(File.dirname(__FILE__), 'sms_nexmo'))

        @alert  = alert
        bnd     = binding

        begin
          message = sms_template_erb.result(bnd).chomp
        rescue => e
          @logger.error "Error while executing the ERB for a Nexmo SMS: " +
            "ERB being executed: #{sms_template}"
          raise
        end

        if @config.nil? || (@config.respond_to?(:empty?) && @config.empty?)
          @logger.error "Nexmo config is missing"
          return
        end

        errors = []

        safe_message = truncate(message, 159)

        [[api_key, "Nexmo api_key is missing"],
         [secret, "Nexmo auth_token is missing"],
         [from,  "SMS from address is missing"],
         [address,  "SMS address is missing"],
         [notification_id, "Notification id is missing"]].each do |val_err|

          next unless val_err.first.nil? || (val_err.first.respond_to?(:empty?) && val_err.first.empty?)
          errors << val_err.last
        end

        unless errors.empty?
          errors.each {|err| @logger.error err }
          return
        end

        begin
          nexmo = Nexmo::Client.new(key: api_key, secret: secret)
          nexmo.send_message(from: from, to: address, text: safe_message)
          @sent += 1
        rescue => e
          @logger.error "Error sending SMS via Nexmo: #{e.message}"
        end
      rescue => e
        @logger.error "Error generating or delivering Nexmo SMS to #{alert.address}: #{e.class}: #{e.message}"
        @logger.error e.backtrace.join("\n")
        raise
      end
    end
  end
end
