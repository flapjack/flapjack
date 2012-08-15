#!/usr/bin/env ruby

require 'net/http'
require 'flapjack'

module Flapjack
  module Notification
    class SmsMessagenet

      def self.sender(notification, options = {})
        
        log = options[:logger]
        config = options[:config]
        
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
        log.debug("request_uri: #{uri.request_uri.inspect}")

        Net::HTTP.start(uri.host, uri.port, :use_ssl => uri.scheme == 'https') do |http|
          request = Net::HTTP::Get.new uri.request_uri
          response = http.request request
          http_success = ( response.is_a?(Net::HTTPSuccess) == true )
          log.debug("Flapjack::Notification::SMSMessagenet: response from server: #{response.body}")
          raise RuntimeError.new "Failed to send SMS via messagenet, http response is a #{response.class}, notification_id: #{notification_id}" unless http_success
        end

      end
    end
  end
end


