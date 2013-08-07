#!/usr/bin/env ruby

require 'net/http'
require 'uri'
require 'uri/https'

module Flapjack
  module Gateways
    class SmsMessagenet

      include MonitorMixin

      attr_reader :sent

      def initialize(opts = {})
        @config = opts[:config]
        @redis_config = opts[:redis_config] || {}
        @logger = opts[:logger]
        @redis = Redis.new(@redis_config.merge(:driver => :hiredis))

        @notifications_queue = @config['queue'] || 'sms_notifications'

        @sent = 0

        mon_initialize

        @logger.debug("new sms gateway pikelet with the following options: #{@config.inspect}")
      end

      def start
        loop do
          synchronize do
            Flapjack::Data::Message.foreach_on_queue(@notifications_queue, :redis => @redis) {
              handle_message(message)
            }
          end

          Flapjack::Data::Message.wait_for_queue(@notifications_queue, :redis => @redis)
        end

      rescue Flapjack::PikeletStop => fps
        @logger.info "stopping sms_messagenet notifier"
      end

      def stop(thread)
        synchronize do
          thread.raise Flapjack::PikeletStop.new
        end
      end

      def handle_message(msg)
        @logger.debug "Woo, got a message to send out: #{msg.inspect}"

        notification_type  = msg['notification_type']
        contact_first_name = msg['contact_first_name']
        contact_last_name  = msg['contact_last_name']
        state              = msg['state']
        summary            = msg['summary']
        time               = msg['time']
        entity, check      = msg['event_id'].split(':', 2)

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

        # TODO log error and skip instead of raising errors
        if @config.nil? || (@config.respond_to?(:empty?) && @config.empty?)
          @logger.error "Messagenet config is missing"
          return
        end

        errors = []

        username = @config["username"]
        password = @config["password"]
        address  = msg['address']
        msg_id   = msg['id']

        [[username, "Messagenet username is missing"],
         [password, "Messagenet password is missing"],
         [address,  "SMS address is missing"],
         [message,  "SMS message is missing"],
         [msg_id, "Message id is missing"]].each do |val_err|

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

        # TODO ensure we're not getting a cached response from a proxy or similar,
        # use appropriate headers etc.

        uri = URI::HTTPS.build(:host => 'www.messagenet.com.au',
                              :path => '/dotnet/Lodge.asmx/LodgeSMSMessage',
                              :query => URI.encode_www_form(query))
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        request = Net::HTTP::Get.new(uri.request_uri)

        http_response = http.request(request)

        @logger.debug "server response: #{http_response.inspect}"

        status = http_response.code

        if (status.to_i >= 200) && (status.to_i <= 206)
          @sent += 1
          @logger.info "Sent SMS via Messagenet, response status is #{status}, " +
            "msg_id: #{msg_id}"
        else
          @logger.error "Failed to send SMS via Messagenet, response status is #{status}, " +
            "msg_id: #{msg_id}"
        end

      end
    end
  end
end

