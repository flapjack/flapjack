#!/usr/bin/env ruby

require 'mail'
require 'erb'
require 'socket'
require 'chronic_duration'

require 'hiredis'
require 'redis'

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
        @redis_config = opts[:redis_config] || {}
        @logger = opts[:logger]
        @redis = Redis.new(@redis_config.merge(:driver => :hiredis))

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
            Flapjack::Data::Message.foreach_on_queue(@notifications_queue, :redis => @redis, :logger => @logger) {|message|
              handle_message(message)
            }
          end

          @logger.debug "blocking on messages"
          Flapjack::Data::Message.wait_for_queue(@notifications_queue, :redis => @redis)
        end
      end

      def stop_type
        :exception
      end

      def handle_message(message)
        @logger.debug "Woo, got a message to send out: #{message.inspect}"

        @notification_type          = message['notification_type']
        @contact_first_name         = message['contact_first_name']
        @contact_last_name          = message['contact_last_name']
        @state                      = message['state']
        @summary                    = message['summary']
        @last_state                 = message['last_state']
        @last_summary               = message['last_summary']
        @details                    = message['details']
        @time                       = message['time']
        @relative                   = relative_time_ago(Time.at(@time))
        @entity_name, @check        = message['event_id'].split(':', 2)

        entity_check = Flapjack::Data::EntityCheck.for_event_id(message['event_id'],
          :redis => @redis)

        @in_unscheduled_maintenance = entity_check.in_scheduled_maintenance?
        @in_scheduled_maintenance   = entity_check.in_unscheduled_maintenance?

        # FIXME: I can't get the entity_check.last_change to work in this context
        # it always returns nil, despite entity_check being a good looking EntityCheck object
        # and all ...
        if lc = entity_check.last_change
          duration  = (Time.now.to_i - lc)
          @duration = (duration && duration > 40) ? duration : nil
        end

        headline_map = {'problem'         => 'Problem: ',
                        'recovery'        => 'Recovery: ',
                        'acknowledgement' => 'Acknowledgement: ',
                        'test'            => 'Test Notification: ',
                        'unknown'         => ''
                       }

        headline = headline_map[@notification_type] || ''

        @subject = "#{headline}'#{@check}' on #{@entity_name}"
        @subject += " is #{@state.upcase}" unless ['acknowledgement', 'test'].include?(@notification_type)

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
        text_template = ERB.new(File.read(File.dirname(__FILE__) +
          '/email/alert.text.erb'))

        html_template = ERB.new(File.read(File.dirname(__FILE__) +
          '/email/alert.html.erb'))

        bnd = binding

        Mail.new do
          from     opts[:from]
          to       opts[:to]
          subject  opts[:subject]
          reply_to opts[:from]

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

