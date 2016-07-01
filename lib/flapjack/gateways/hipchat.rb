#!/usr/bin/env ruby

require 'em-synchrony'
require 'em-synchrony/em-http'
require 'active_support/inflector'

require 'flapjack/redis_pool'

require 'flapjack/data/alert'
require 'flapjack/utility'

module Flapjack
  module Gateways
    class Hipchat

      include Flapjack::Utility

      def initialize(opts = {})
        @config = opts[:config]
        @logger = opts[:logger]
        @redis_config = opts[:redis_config] || {}
        @redis = Flapjack::RedisPool.new(:config => @redis_config, :size => 1, :logger => @logger)

        @logger.info("starting")
        @logger.debug("new hipchat gateway pikelet with the following options: #{@config.inspect}")

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
            @logger.debug("hipchat gateway is going into blpop mode on #{queue}")
            alert = Flapjack::Data::Alert.next(queue, :redis => @redis, :logger => @logger)
            deliver(alert) unless alert.nil?
          rescue => e
            @logger.error "Error generating or dispatching Hipchat message: #{e.class}: #{e.message}\n" +
              e.backtrace.join("\n")
          end
        end
      end

      def deliver(alert)
      	access_token = @config["access_token"]
        endpoint     = @config["endpoint"]
      	room         = @config["room"]

        notification_id = alert.notification_id
        message_type    = alert.rollup ? 'rollup' : 'alert'

        hipchat_template_erb, hipchat_template =
          load_template(@config['templates'], message_type, 'text',
                        File.join(File.dirname(__FILE__), 'hipchat'))

        @alert  = alert
        bnd     = binding

        begin
          message = hipchat_template_erb.result(bnd).chomp
        rescue => e
          @logger.error "Error while executing the ERB for a hipchat message: " +
            "ERB being executed: #{hipchat_template}"
          raise
        end

        errors = []

        [  
         [access_token, "Hipchat endpoint is missing"],
         [endpoint, "Hipchat endpoint is missing"],
         [room, "Hipchat room is missing"]
        ].each do |val_err|

          next unless val_err.first.nil? || (val_err.first.respond_to?(:empty?) && val_err.first.empty?)
          errors << val_err.last
        end

        unless errors.empty?
          errors.each {|err| @logger.error err }
          return
        end
        
        payload = Flapjack.dump_json(
          'message_format'    => 'text',
          'color'             => message =~ /Problem:/ ? 'red' : 'green',
          'message'           => message,
        )
        
        http = EM::HttpRequest.new("#{endpoint}/room/#{room}/notification?auth_token=#{access_token}").post(:body => payload, :head => {'Content-Type' => 'application/json'})
 
        status = (http.nil? || http.response_header.nil?) ? nil : http.response_header.status

        @logger.debug "payload: #{payload.inspect}"

        http = EM::HttpRequest.new("#{endpoint}").post(:body => {'payload' => payload})

        @logger.debug "server response: #{http.response}"

        status = (http.nil? || http.response_header.nil?) ? nil : http.response_header.status
        if (status >= 200) && (status <= 206)
          @sent += 1
          alert.record_send_success!
          @logger.debug "Sent message via Hipchat, response status is #{status}, " +
            "notification_id: #{notification_id}"
        else
          @logger.error "Failed to send message via Hipchat, response status is #{status}, " +
            "notification_id: #{notification_id}"
        end
      rescue => e
        @logger.error "Error generating or delivering hipchat message to #{alert.address}: #{e.class}: #{e.message}"
        @logger.error e.backtrace.join("\n")
        raise
      end

    end
  end
end

