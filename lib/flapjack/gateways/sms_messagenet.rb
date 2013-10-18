#!/usr/bin/env ruby

require 'em-synchrony'
require 'em-synchrony/em-http'
require 'active_support/inflector'

require 'flapjack/data/alert'
require 'flapjack/utility'

module Flapjack
  module Gateways
    class SmsMessagenet

      MESSAGENET_DEFAULT_URL = 'https://www.messagenet.com.au/dotnet/Lodge.asmx/LodgeSMSMessage'

      class << self

        include Flapjack::Utility

        def start
          @sent = 0
        end

        def perform(contents)
          @logger.debug "Woo, got a notification to send out: #{contents.inspect}"
          alert = Flapjack::Data::Alert.new(contents)

          endpoint = @config["endpoint"] || MESSAGENET_DEFAULT_URL
          username = @config["username"]
          password = @config["password"]

          address         = alert.address
          notification_id = alert.notification_id

          message_type = case
          when @rollup
            'rollup'
          else
            'alert'
          end

          sms_template = ERB.new(File.read(File.dirname(__FILE__) +
            "/sms_messagenet/#{message_type}.text.erb"), nil, '-')

          @alert  = alert
          bnd     = binding
          message = sms_template.result(bnd).chomp

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
            @logger.info "Sent SMS via Messagenet, response status is #{status}, " +
              "notification_id: #{notification_id}"
          else
            @logger.error "Failed to send SMS via Messagenet, response status is #{status}, " +
              "notification_id: #{notification_id}"
          end
        rescue => e
          @logger.error "Error delivering sms to #{alert.address}: #{e.class}: #{e.message}"
          @logger.error e.backtrace.join("\n")
          raise
        end

      end
    end
  end
end

