#!/usr/bin/env ruby

require 'net/http'
require 'flapjack'

module Flapjack
  class Notification::SmsMessagenet

    def sender(notification)
      username = Flapjack.config("sms_messagenet_username") || raise RuntimeError "config sms_messagenet_username is not defined"
      password = Flapjack.config("sms_messagenet_password") || raise RuntimeError "config sms_messagenet_password is not defined"

      address         = notification[:address]
      message         = notification[:message]
      notification_id = notification[:id]

      params = { 'Username'     => username,
                 'Pwd'          => password,
                 'PhoneNumber'  => address,
                 'PhoneMessage' => message }

      uri       = URI('https://www.messagenet.com.au/dotnet/Lodge.asmx/LodgeSMSMessage')
      uri.query = URI.encode_www_form(params)

      Net::HTTP.start(uri.host, uri.port, :use_ssl => uri.scheme == 'https') do |http|
        request = Net::HTTP::Get.new uri.request_uri
        response = http.request request
        http_success = ( response.is_a?(Net::HTTPSuccess) == true )
        @@logger.debug("Flapjack::Notification::SMSMessagenet: response from server: #{response.body}")
        raise RuntimeError "Failed to send SMS via messagenet, http response is a #{response.class}, notification_id: #{notification_id}" unless http_success
      end

    end
  end
end


