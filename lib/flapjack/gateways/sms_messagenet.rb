#!/usr/bin/env ruby

require 'em-synchrony'
require 'em-synchrony/em-http'
require 'active_support/inflector'

module Flapjack
  module Gateways
    class SmsMessagenet

      MESSAGENET_DEFAULT_URL = 'https://www.messagenet.com.au/dotnet/Lodge.asmx/LodgeSMSMessage'

      class << self

        def start
          @sent = 0
        end

        def perform(notification)
          @logger.debug "Woo, got a notification to send out: #{notification.inspect}"

          endpoint = @config["endpoint"] || MESSAGENET_DEFAULT_URL
          username = @config["username"]
          password = @config["password"]

          @notification_type   = notification['notification_type']
          @rollup              = notification['rollup']
          @rollup_alerts       = notification['rollup_alerts']
          @state               = notification['state']
          @summary             = notification['summary']
          @time                = notification['time']
          @entity_name, @check = notification['event_id'].split(':', 2)
          address              = notification['address']
          notification_id      = notification['id']

          message_type = case
          when @rollup
            'rollup'
          else
            'alert'
          end

          sms_template = ERB.new(File.read(File.dirname(__FILE__) +
            "/sms_messagenet/#{message_type}.erb"), nil, '-')

          bnd     = binding
          message = sms_template.result(bnd).chomp

          # TODO log error and skip instead of raising errors
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

        end

        # copied from ActiveSupport
        def truncate(str, length, options = {})
          text = str.dup
          options[:omission] ||= "..."

          length_with_room_for_omission = length - options[:omission].length
          stop = options[:separator] ?
            (text.rindex(options[:separator], length_with_room_for_omission) || length_with_room_for_omission) : length_with_room_for_omission

          (text.length > length ? text[0...stop] + options[:omission] : text).to_s
        end

      end
    end
  end
end

