#!/usr/bin/env ruby

require 'em-synchrony'
require 'em-synchrony/em-http'
require 'active_support/inflector'

require 'flapjack/data/alert'
require 'flapjack/utility'

module Flapjack
  module Gateways
    class AwsSns

      SNS_DEFAULT_REGION_NAME = 'us-east-1'

      class << self

        include Flapjack::Utility

        def start
          @sent = 0
        end

        def perform(contents)
          @logger.debug "Received a notification: #{contents.inspect}"
          alert = Flapjack::Data::Alert.new(contents, :logger => @logger)

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

          string_to_sign = string_to_sign('POST', hostname, "/", query)

          query['Signature'] = get_signature(secret_key, string_to_sign)

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

        def get_signature(secret_key, string_to_sign)
          signature = OpenSSL::HMAC.digest('sha256', secret_key, string_to_sign)

          Base64.encode64(signature).strip
        end

        def string_to_sign(method, host, uri, query)
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
end

