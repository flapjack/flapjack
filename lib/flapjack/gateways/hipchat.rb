#!/usr/bin/env ruby

require 'em-synchrony'
require 'em-synchrony/em-http'
require 'active_support/inflector'

require 'flapjack/redis_pool'

require 'flapjack/data/alert'
require 'flapjack/utility'
require 'hipchat'

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
          
        api_token     = @config["api_token"]
        @username     = @config["username"]
        @room         = @config["room"]
        
        errors = []

        [  
         [api_token, "Hipchat api_token is missing"],
         [@username, "Hipchat username is missing"],  
         [@room, "Hipchat room is missing"]
        ].each do |val_err|

          next unless val_err.first.nil? || (val_err.first.respond_to?(:empty?) && val_err.first.empty?)
          errors << val_err.last
        end

        unless errors.empty?
          errors.each {|err| @logger.error err }
          return 
        end
        
        @client = HipChat::Client.new(api_token, :api_version => 'v2')
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
        
        payload = {
          :message_format    => 'html',
          :color             => @alert.state == 'ok' ? 'green' : 'red'
        }
        
        reported_payload = payload.merge(:message => message)
        
        @logger.debug "payload: #{reported_payload}"

        begin
          @client[@room].send(@username, message, payload)
          @sent += 1
          alert.record_send_success!
          @logger.debug "Sent message via Hipchat"
        rescue HipChat::UnknownRoom  
          @logger.error "Failed to send message via Hipchat. Unknown room #{@room}"
        end
      rescue => e
        @logger.error "Error generating or delivering hipchat message to #{alert.address}: #{e.class}: #{e.message}"
        @logger.error e.backtrace.join("\n")
        raise
      end

    end
  end
end

