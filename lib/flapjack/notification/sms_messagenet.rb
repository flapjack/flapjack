#!/usr/bin/env ruby

require 'log4r'
require 'log4r/outputter/syslogoutputter'
require 'net/http'
require 'flapjack'

module Flapjack
  module Notification
    class SmsMessagenet

      def self.sender(notification, log)

        raise RuntimeError.new('sms_messagenet_username is missing') unless username = Flapjack.config["sms_messagenet_username"] #"config sms_messagenet_username is not defined"
        raise RuntimeError.new('sms_messagenet_password is missing') unless password = Flapjack.config["sms_messagenet_password"] #"config sms_messagenet_password is not defined"

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


