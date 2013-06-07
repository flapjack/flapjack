#!/usr/bin/env ruby

require 'em-synchrony'
require 'em-synchrony/em-http'

module Flapjack
  module Gateways
    class SmsMessagenet

      MESSAGENET_URL = 'https://www.messagenet.com.au/dotnet/Lodge.asmx/LodgeSMSMessage'

      class << self

        def pikelet_settings
          {:em_synchrony => false,
           :em_stop      => true}
        end

        def start
          @sent = 0
        end

        def perform(notification)
          @logger.debug "Woo, got a notification to send out: #{notification.inspect}"

          notification_type  = notification['notification_type']
          contact_first_name = notification['contact_first_name']
          contact_last_name  = notification['contact_last_name']
          state              = notification['state']
          summary            = notification['summary']
          time               = notification['time']
          entity, check      = notification['event_id'].split(':')

          headline_map = {'problem'         => 'PROBLEM: ',
                          'recovery'        => 'RECOVERY: ',
                          'acknowledgement' => 'ACK: ',
                          'test'            => 'TEST NOTIFICATION: ',
                          'unknown'         => '',
                          ''                => '',
                         }

          headline = headline_map[notification_type] || ''

          message = "#{headline}'#{check}' on #{entity}"
          message += " is #{state.upcase}" unless ['acknowledgement', 'test'].include?(notification_type)
          message += " at #{Time.at(time).strftime('%-d %b %H:%M')}, #{summary}"

          notification['message'] = message

          # TODO log error and skip instead of raising errors
          if @config.nil? || (@config.respond_to?(:empty?) && @config.empty?)
            @logger.error "Messagenet config is missing"
            return
          end

          errors = []

          username = @config["username"]
          password = @config["password"]
          address  = notification['address']
          message  = notification['message']
          notification_id = notification['id']

          [[username, "Messagenet username is missing"],
           [password, "Messagenet password is missing"],
           [address,  "SMS address is missing"],
           [message,  "SMS message is missing"],
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
                   'PhoneMessage' => message}

          http = EM::HttpRequest.new(MESSAGENET_URL).get(:query => query)

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
      end
    end
  end
end

