#!/usr/bin/env ruby

require 'net/http'
require 'uri'
require 'uri/https'

require 'flapjack'

require 'flapjack/data/message'

require 'flapjack/exceptions'

module Flapjack
  module Gateways
    class SmsMessagenet

      MESSAGENET_DEFAULT_HOST = 'www.messagenet.com.au'
      MESSAGENET_DEFAULT_PATH = '/dotnet/Lodge.asmx/LodgeSMSMessage'

      attr_reader :sent

      def initialize(opts = {})
        @lock = opts[:lock]

        @config = opts[:config]
        @logger = opts[:logger]

        @notifications_queue = @config['queue'] || 'sms_notifications'

        @sent = 0

        @logger.debug("new sms gateway pikelet with the following options: #{@config.inspect}")
      end

      def start
        loop do
          @lock.synchronize do
            Flapjack::Data::Message.foreach_on_queue(@notifications_queue,
                                                     :logger => @logger) {|message|
              handle_message(message)
            }
          end

          Flapjack::Data::Message.wait_for_queue(@notifications_queue)
        end
      end

      def stop_type
        :exception
      end

      def handle_message(msg)
        @logger.debug "Woo, got a message to send out: #{msg.inspect}"

        endpoint_host = @config["endpoint_host"] || MESSAGENET_DEFAULT_HOST
        endpoint_path = @config["endpoint_path"] || MESSAGENET_DEFAULT_PATH
        username = @config["username"]
        password = @config["password"]

        @notification_type   = msg['notification_type']
        @rollup              = msg['rollup']
        @rollup_alerts       = msg['rollup_alerts']
        @state               = msg['state']
        @summary             = msg['summary']
        @time                = msg['time']
        @entity_name, @check = msg['event_id'].split(':', 2)
        address              = msg['address']
        msg_id               = msg['id']

        message_type = case
        when @rollup
          'rollup'
        else
          'alert'
        end

        sms_template = ERB.new(File.read(File.dirname(__FILE__) +
        "/sms_messagenet/#{message_type}.text.erb"), nil, '-')

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

        uri = URI::HTTPS.build(:host => endpoint_host,
                               :path => endpoint_path,
                               :port => 443,
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

