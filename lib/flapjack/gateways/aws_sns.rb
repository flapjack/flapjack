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
    class AwsSns

      SNS_DEFAULT_REGION_NAME = 'us-east-1'

      attr_accessor :sent

      include Flapjack::Utility

      def initialize(opts = {})
        @lock = opts[:lock]

        @config = opts[:config]

        # TODO support for config reloading
        @queue = Flapjack::RecordQueue.new(@config['queue'] || 'sns_notifications',
                   Flapjack::Data::Alert)

        @sent = 0

        Flapjack.logger.debug("new sns gateway pikelet with the following options: #{@config.inspect}")
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
        Flapjack.logger.debug "Received a notification: #{alert.inspect}"

        region_name = @config["region_name"] || SNS_DEFAULT_REGION_NAME
        hostname = "sns.#{region_name}.amazonaws.com"
        endpoint = "http://#{hostname}/"
        access_key = @config["access_key"]
        secret_key = @config["secret_key"]
        timestamp = Time.at(alert.time).utc.strftime('%Y-%m-%dT%H:%M:%SZ')

        address         = alert.medium.address
        notification_id = alert.id
        message_type    = alert.rollup ? 'rollup' : 'alert'

        aws_sns_subject_template_erb, aws_sns_subject_template =
          load_template(@config['templates'], "#{message_type}_subject",
                        'text', File.join(File.dirname(__FILE__), 'aws_sns'))

        aws_sns_template_erb, aws_sns_template =
          load_template(@config['templates'], message_type, 'text',
                        File.join(File.dirname(__FILE__), 'aws_sns'))

        @alert  = alert
        @check  = alert.check
        bnd     = binding

        begin
          erb_to_be_executed = aws_sns_subject_template
          subject = aws_sns_subject_template_erb.result(bnd).chomp

          erb_to_be_executed = aws_sns_template
          message = aws_sns_template_erb.result(bnd).chomp
        rescue => e
          Flapjack.logger.error "Error while executing the ERB for an AWS SNS message: " +
            "ERB being executed: #{erb_to_be_executed}"
          raise
        end

        if @config.nil? || (@config.respond_to?(:empty?) && @config.empty?)
          Flapjack.logger.error "AWS SNS config is missing"
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
          errors.each {|err| Flapjack.logger.error err }
          return
        end

        query = {'Subject'          => (subject.length > 100) ?
                                       subject[0..99].gsub(/...$/, '...') : subject,
                 'TopicArn'         => address,
                 'Message'          => message,
                 'Action'           => 'Publish',
                 'SignatureVersion' => 2,
                 'SignatureMethod'  => 'HmacSHA256',
                 'Timestamp'        => timestamp,
                 'AWSAccessKeyId'   => access_key.upcase}

        # TODO ensure we're not getting a cached response from a proxy or similar,
        # use appropriate headers etc.
        string_sign = self.class.string_to_sign('POST', hostname, "/", query)

        query['Signature'] = self.class.get_signature(secret_key, string_sign)

        req = Net::HTTP::Post.new(endpoint)
        req.set_form_data(query)

        http_response = Net::HTTP.start(hostname) do |http|
          http.request(req)
        end

        Flapjack.logger.debug "server response: #{http_response.inspect}"

        status = http_response.code

        if (status.to_i >= 200) && (status.to_i <= 206)
          @sent += 1
          Flapjack.logger.debug "Sent notification via SNS, response status is #{status}, " +
            "notification_id: #{notification_id}"
        else
          Flapjack.logger.error "Failed to send notification via SNS, response status is #{status}, " +
            "notification_id: #{notification_id}"
        end

      rescue => e
        Flapjack.logger.error "Error generating or delivering notification to #{address}: #{e.class}: #{e.message}"
        Flapjack.logger.error e.backtrace.join("\n")
        raise
      end

      def self.get_signature(secret_key, string_to_sign)
        signature = OpenSSL::HMAC.digest('sha256', secret_key, string_to_sign)

        Base64.encode64(signature).strip
      end

      def self.string_to_sign(method, host, uri, query)
        encoded_query = query.keys.sort.collect {|key|
          k = URI.encode_www_form_component(key)
          v = URI.encode_www_form_component(query[key].to_s)
          "#{k}=#{v}"
        }.join("&")

        [method.upcase,
         host.downcase,
         uri,
         encoded_query
        ].join("\n")
      end

    end
  end
end
