#!/usr/bin/env ruby

require 'mail'
require 'erb'
require 'socket'
require 'chronic_duration'
require 'active_support/inflector'

require 'flapjack'

require 'flapjack/exceptions'
require 'flapjack/utility'

require 'flapjack/data/entity_check'
require 'flapjack/data/message'

module Flapjack
  module Gateways

    class Email

      include Flapjack::Utility

      attr_reader :sent

      def initialize(opts = {})
        @lock = opts[:lock]
        @config = opts[:config]
        @logger = opts[:logger]

        # TODO support for config reloading
        @notifications_queue = @config['queue'] || 'email_notifications'

        if smtp_config = @config['smtp_config']
          @host = smtp_config['host'] || 'localhost'
          @port = smtp_config['port'] || 25

          # NB: needs testing
          if smtp_config['authentication'] && smtp_config['username'] &&
            smtp_config['password']

            @auth = {:authentication => smtp_config['authentication'],
                     :username => smtp_config['username'],
                     :password => smtp_config['password'],
                     :enable_starttls_auto => true
                    }
          end

        else
          @host = 'localhost'
          @port = 25
        end

        @sent = 0
      end

      def start
        @logger.info("starting")
        @logger.debug("new email gateway pikelet with the following options: #{@config.inspect}")

        msg_raw = nil

        loop do
          @lock.synchronize do
            @logger.debug "checking messages"
            Flapjack::Data::Message.foreach_on_queue(@notifications_queue, :logger => @logger) {|message|
              handle_message(message)
            }
          end

          @logger.debug "blocking on messages"
          Flapjack::Data::Message.wait_for_queue(@notifications_queue)
        end
      end

      def stop_type
        :exception
      end

      def handle_message(message)
        @logger.debug "Woo, got a message to send out: #{message.inspect}"

        # The instance variables are referenced by the templates, which
        # share the current binding context
        @notification_type   = message['notification_type']
        @notification_id     = message['id'] || SecureRandom.uuid
        @rollup              = message['rollup']
        @rollup_alerts       = message['rollup_alerts']
        @rollup_threshold    = message['rollup_threshold']
        @contact_first_name  = message['contact_first_name']
        @contact_last_name   = message['contact_last_name']
        @state               = message['state']
        @duration            = message['state_duration']
        @summary             = message['summary']
        @last_state          = message['last_state']
        @last_summary        = message['last_summary']
        @details             = message['details']
        @time                = message['time']
        @entity_name, @check = message['event_id'].split(':', 2)

        entity_check = Flapjack::Data::EntityCheck.for_event_id(message['event_id'])

        @in_unscheduled_maintenance = entity_check.in_unscheduled_maintenance?
        @in_scheduled_maintenance   = entity_check.in_scheduled_maintenance?

        fqdn       = `/bin/hostname -f`.chomp
        m_from     = "flapjack@#{fqdn}"
        @logger.debug("flapjack_mailer: set from to #{m_from}")
        m_reply_to = m_from
        m_to       = message['address']

        @logger.debug("sending Flapjack::Notification::Email " +
          "#{message['id']} to: #{m_to} subject: #{@subject}")

        mail = prepare_email(:subject => @subject,
                             :from => m_from,
                             :to => m_to)

        # TODO a cleaner way to not step on test delivery settings
        # (don't want to stub in Cucumber)
        unless defined?(FLAPJACK_ENV) && 'test'.eql?(FLAPJACK_ENV)
          mail.delivery_method(:smtp, {:address => @host,
                                       :port => @port}.merge(@auth || {}))
        end

        # any exceptions will be propagated through to main pikelet handler
        mail.deliver

        @logger.info "Email sending succeeded"
        @sent += 1
      end

      private

      def prepare_email(opts = {})
        from       = opts[:from]
        to         = opts[:to]
        message_id = "<#{@notification_id}@#{@fqdn}>"

        message_type = case
        when @rollup
          'rollup'
        else
          'alert'
        end

        subject_template = ERB.new(File.read(File.dirname(__FILE__) +
          "/email/#{message_type}_subject.text.erb"), nil, '-')

        text_template = ERB.new(File.read(File.dirname(__FILE__) +
          "/email/#{message_type}.text.erb"), nil, '-')

        html_template = ERB.new(File.read(File.dirname(__FILE__) +
          "/email/#{message_type}.html.erb"), nil, '-')

        bnd = binding
        subject    = subject_template.result(bnd).chomp

        @logger.debug("preparing email to: #{to}, subject: #{subject}, message-id: #{message_id}")

        Mail.new do
          from       from
          to         to
          subject    subject
          reply_to   from
          message_id message_id

          text_part do
            body text_template.result(bnd)
          end

          html_part do
            content_type 'text/html; charset=UTF-8'
            body html_template.result(bnd)
          end
        end
      end
    end

  end
end

