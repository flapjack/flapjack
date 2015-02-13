#!/usr/bin/env ruby

require 'em-synchrony'
require 'em-synchrony/em-http'
require 'active_support/inflector'

require 'flapjack/redis_pool'

require 'flapjack/data/alert'
require 'flapjack/utility'

module Flapjack
  module Gateways
    class AwsSns

      SNS_DEFAULT_REGION_NAME = 'us-east-1'

      include Flapjack::Utility

      def initialize(opts = {})
        @config = opts[:config]
        @logger = opts[:logger]
        @redis_config = opts[:redis_config] || {}
        @redis = Flapjack::RedisPool.new(:config => @redis_config, :size => 1, :logger => @logger)

        @logger.info("starting")
        @logger.debug("new aws_sns gateway pikelet with the following options: #{@config.inspect}")

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
            @logger.debug("aws_sns gateway is going into blpop mode on #{queue}")
            alert = Flapjack::Data::Alert.next(queue, :redis => @redis, :logger => @logger)
            deliver(alert) unless alert.nil?
          rescue => e
            @logger.error "Error generating or dispatching AWS SNS message: #{e.class}: #{e.message}\n" +
              e.backtrace.join("\n")
          end
        end
      end

      def deliver(alert)
        region_name = @config["region_name"] || SNS_DEFAULT_REGION_NAME
        hostname = "sns.#{region_name}.amazonaws.com"
        endpoint = "http://#{hostname}/"
        access_key = @config["access_key"]
        secret_key = @config["secret_key"]
        timestamp = @config["timestamp"] || DateTime.now.iso8601

        address         = alert.address
        notification_id = alert.notification_id
        message_type    = alert.rollup ? 'rollup' : 'alert'

        my_dir = File.dirname(__FILE__)
        sms_template_path = case
        when @config.has_key?('templates') && @config['templates']["#{message_type}.text"]
          @config['templates']["#{message_type}.text"]
        else
          my_dir + "/aws_sns/#{message_type}.text.erb"
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
          @logger.error "AWS SNS config is missing"
          return
        end

        errors = []

        [[address, "AWS SNS topic ARN is missing"],
         [access_key, "AWS SNS access key is missing"],
         [secret_key,  "AWS SNS secret key is missing"],
         [notification_id, "Notification id is missing"]].each do |val_err|

          next unless val_err.first.nil? || (val_err.first.respond_to?(:empty?) && val_err.first.empty?)
          errors << val_err.last
        end

        unless errors.empty?
          errors.each {|err| @logger.error err }
          return
        end

        query = {'Subject'          => message,
                 'TopicArn'         => address,
                 'Message'          => message,
                 'Action'           => 'Publish',
                 'SignatureVersion' => 2,
                 'SignatureMethod'  => 'HmacSHA256',
                 'Timestamp'        => timestamp,
                 'AWSAccessKeyId'   => access_key}

        string_to_sign = self.class.string_to_sign('POST', hostname, "/", query)

        query['Signature'] = self.class.get_signature(secret_key, string_to_sign)

        http = EM::HttpRequest.new(endpoint).post(:query => query)

        @logger.debug "server response: #{http.response}"

        status = (http.nil? || http.response_header.nil?) ? nil : http.response_header.status
        if (status >= 200) && (status <= 206)
          @sent += 1
          alert.record_send_success!
          @logger.debug "Sent notification via SNS, response status is #{status}, " +
            "notification_id: #{notification_id}"
        else
          @logger.error "Failed to send notification via SNS, response status is #{status}, " +
            "notification_id: #{notification_id}"
        end
      rescue => e
        @logger.error "Error generating or delivering notification to #{address}: #{e.class}: #{e.message}"
        @logger.error e.backtrace.join("\n")
        raise
      end

      def self.get_signature(secret_key, string_to_sign)
        signature = OpenSSL::HMAC.digest('sha256', secret_key, string_to_sign)

        Base64.encode64(signature).strip
      end

      def self.string_to_sign(method, host, uri, query)
        query = query.sort_by { |key, value| key }

        [method.upcase,
         host.downcase,
         uri,
         URI.encode_www_form(query)
        ].join("\n")
      end

    end
  end
end

