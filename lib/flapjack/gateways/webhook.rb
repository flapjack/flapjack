#!/usr/bin/env ruby

require 'em-synchrony'
require 'em-synchrony/em-http'
require 'active_support/inflector'

require 'flapjack/redis_pool'

require 'flapjack/data/alert'
require 'flapjack/utility'

module Flapjack
  module Gateways
    class Webhook

      include Flapjack::Utility

      def initialize(opts = {})
        @config = opts[:config]
        @logger = opts[:logger]
        @redis_config = opts[:redis_config] || {}
        @redis = Flapjack::RedisPool.new(:config => @redis_config, :size => 1, :logger => @logger)

        @logger.info("starting")
        @logger.debug("new webhook gateway pikelet with the following options: #{@config.inspect}")

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
            @logger.debug("webhook gateway is going into blpop mode on #{queue}")
            alert = Flapjack::Data::Alert.next(queue, :redis => @redis, :logger => @logger)
            deliver(alert) unless alert.nil?
          rescue => e
            @logger.error "Error generating or dispatching Webhook message: #{e.class}: #{e.message}\n" +
              e.backtrace.join("\n")
          end
        end
      end

      def deliver(alert)
        hash = {}
        alert.instance_variables.each do |var|
          if var.to_s.delete("@") != "logger"
            hash[var.to_s.delete("@")] = alert.instance_variable_get(var)
          end
        end
        notification_id = alert.notification_id
        message_type    = alert.rollup ? 'rollup' : 'alert'
        
        payload = Flapjack.dump_json({
          'alert' => hash,
          'id' => notification_id,
          'type' => message_type,
        })

        @logger.debug "payload: #{payload.inspect}"

        if @config['hooks'] && @config['hooks'].length > 0
          @config['hooks'].each do |hook|
            @logger.info("Posting to #{hook['url']} with timeout #{hook['timeout']}")

            begin
              http = EM::HttpRequest.new(hook['url']).post(:body => payload, :head => {'Content-Type' => 'application/json'}, :inactivity_timeout => hook['timeout'])
              @logger.debug "server response: #{http.response}"

              status = (http.nil? || http.response_header.nil?) ? nil : http.response_header.status
              if (status >= 200) && (status <= 206)
                @sent += 1
                alert.record_send_success!
                @logger.debug "Sent message via Webhook, response status is #{status}, " +
                  "notification_id: #{notification_id}"
              else
                @logger.error "Failed to send message via Webhook, response status is #{status}, " +
                  "notification_id: #{notification_id}"
              end

            rescue => e
              @logger.error "Error generating or delivering webhook to #{hook['url']}: #{e.class}: #{e.message}"
              @logger.error e.backtrace.join("\n")
              raise
            end
          end
        end
      end
    end
  end
end


