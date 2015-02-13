#!/usr/bin/env ruby

require 'em-synchrony'
require 'em-synchrony/em-http'
require 'active_support/inflector'

require 'flapjack/redis_pool'

require 'flapjack/data/alert'
require 'flapjack/utility'

module Flapjack
  module Gateways
    class SmsMessagenet

      MESSAGENET_DEFAULT_URL = 'https://www.messagenet.com.au/dotnet/Lodge.asmx/LodgeSMSMessage'

      include Flapjack::Utility

      def initialize(opts = {})
        @config = opts[:config]
        @logger = opts[:logger]
        @redis_config = opts[:redis_config] || {}
        @redis = Flapjack::RedisPool.new(:config => @redis_config, :size => 1, :logger => @logger)

        @logger.info("starting")
        @logger.debug("new sms_messagenet gateway pikelet with the following options: #{@config.inspect}")

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
            @logger.debug("sms_messagenet gateway is going into blpop mode on #{queue}")
            alert = Flapjack::Data::Alert.next(queue, :redis => @redis, :logger => @logger)
            deliver(alert) unless alert.nil?
          rescue => e
            @logger.error "Error generating or dispatching SMS Messagenet message: #{e.class}: #{e.message}\n" +
              e.backtrace.join("\n")
          end
        end
      end

      def deliver(alert)
        endpoint = @config["endpoint"] || MESSAGENET_DEFAULT_URL
        username = @config["username"]
        password = @config["password"]

        address         = alert.address
        notification_id = alert.notification_id
        message_type    = alert.rollup ? 'rollup' : 'alert'

        my_dir = File.dirname(__FILE__)
        sms_template_path = case
        when @config.has_key?('templates') && @config['templates']["#{message_type}.text"]
          @config['templates']["#{message_type}.text"]
        else
          my_dir + "/sms_messagenet/#{message_type}.text.erb"
        end
        sms_template = ERB.new(File.read(sms_template_path), nil, '-')

        @alert  = alert
        bnd     = binding

        begin
          message = sms_template.result(bnd).chomp
        rescue => e
          @logger.error "Error while excuting the ERB for an sms: " +
            "ERB being executed: #{sms_template_path}"
          raise
        end

        if @config.nil? || (@config.respond_to?(:empty?) && @config.empty?)
          @logger.error "Messagenet config is missing"
          return
        end

        errors = []

        safe_message = truncate(message, 159)

        [[username, "Messagenet username is missing"],
         [password, "Messagenet password is missing"],
         [address,  "SMS address is missing"],
         [notification_id, "Notification id is missing"]].each do |val_err|

          next unless val_err.first.nil? || (val_err.first.respond_to?(:empty?) && val_err.first.empty?)
          errors << val_err.last
        end

        unless errors.empty?
          errors.each {|err| @logger.error err }
          return
        end

        query = {'Username'     => username,
                 'Pwd'          => password,
                 'PhoneNumber'  => address,
                 'PhoneMessage' => safe_message}

        http = EM::HttpRequest.new(endpoint).get(:query => query)

        @logger.debug "server response: #{http.response}"

        status = (http.nil? || http.response_header.nil?) ? nil : http.response_header.status
        if (status >= 200) && (status <= 206)
          @sent += 1
          alert.record_send_success!
          @logger.debug "Sent SMS via Messagenet, response status is #{status}, " +
            "notification_id: #{notification_id}"
        else
          @logger.error "Failed to send SMS via Messagenet, response status is #{status}, " +
            "notification_id: #{notification_id}"
        end
      rescue => e
        @logger.error "Error generating or delivering sms to #{alert.address}: #{e.class}: #{e.message}"
        @logger.error e.backtrace.join("\n")
        raise
      end

    end
  end
end

