#!/usr/bin/env ruby

require 'net/http'
require 'uri'

require 'flapjack/gateways/base'

module Flapjack
  module Gateways

    class SmsMessagenet
      extend Flapjack::Gateways::Resque

      def self.perform(notification)
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
                        'unknown'         => '',
                        ''                => '',
                       }

        headline = headline_map[notification_type] || ''

        message = "#{headline}'#{check}' on #{entity}"
        message += " is #{state.upcase}" unless notification_type == 'acknowledgement'
        message += " at #{Time.at(time).strftime('%-d %b %H:%M')}, #{summary}"

        notification['message'] = message

        unless config && (username = config["username"])
          raise RuntimeError.new('sms_messagenet: username is missing')
        end
        unless config && (password = config["password"])
          raise RuntimeError.new('sms_messagenet: password is missing')
        end

        raise RuntimeError.new('address is missing') unless address         = notification['address']
        raise RuntimeError.new('message is missing') unless message         = notification['message']
        raise RuntimeError.new('id is missing')      unless notification_id = notification['id']

        params = { 'Username'     => username,
                   'Pwd'          => password,
                   'PhoneNumber'  => address,
                   'PhoneMessage' => message }

        uri       = URI('https://www.messagenet.com.au/dotnet/Lodge.asmx/LodgeSMSMessage')
        uri.query = URI.encode_www_form(params)
        @logger.debug("request_uri: #{uri.request_uri.inspect}")

        Net::HTTP.start(uri.host, uri.port, :use_ssl => uri.scheme == 'https') do |http|
          request = Net::HTTP::Get.new uri.request_uri
          response = http.request request
          http_success = ( response.is_a?(Net::HTTPSuccess) == true )
          @logger.debug("Flapjack::Notification::SMSMessagenet: response from server: #{response.body}")
          raise RuntimeError.new "Failed to send SMS via messagenet, http response is a #{response.class}, notification_id: #{notification_id}" unless http_success
        end

      end
    end

  end
end

