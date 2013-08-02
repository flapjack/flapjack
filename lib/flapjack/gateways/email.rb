#!/usr/bin/env ruby

require 'mail'
require 'erb'
require 'socket'

require 'flapjack/exceptions'
require 'flapjack/utility'

require 'flapjack/data/entity_check'
require 'flapjack/data/message'

module Flapjack
  module Gateways

    class Email

      include MonitorMixin

      include Flapjack::Utility

      def initialize(opts = {})
        @config = opts[:config]
        @redis_config = opts[:redis_config] || {}
        @logger = opts[:logger]
        @redis = Redis.new(@redis_config.merge(:driver => :hiredis))

        @notifications_queue = @config['queue'] || 'email_notifications'

        smtp_config = @config['smtp_config']

        @host = smtp_config ? smtp_config['host'] : 'localhost'
        @port = smtp_config ? smtp_config['port'] : 25

        mon_initialize
      end

      def start
        @logger.info("starting")
        @logger.debug("new email gateway pikelet with the following options: #{@config.inspect}")

        @sent = 0
        msg_raw = nil

        loop do
          synchronize do
            Flapjack::Data::Message.foreach_on_queue(@notifications_queue, :redis => @redis) {|message|
              handle_message(message)
            }
          end

          Flapjack::Data::Message.wait_for_queue(@notifications_queue)
        end

      rescue Flapjack::PikeletStop => fps
        @logger.info "stopping email notifier"
      end

      def stop(thread)
        synchronize do
          thread.raise Flapjack::PikeletStop.new
        end
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

        headline_map = {'problem'         => 'Problem: ',
                        'recovery'        => 'Recovery: ',
                        'acknowledgement' => 'Acknowledgement: ',
                        'test'            => 'Test Notification: ',
                        'unknown'         => ''
                       }

        headline = headline_map[@notification_type] || ''

        @subject = "#{headline}'#{@check}' on #{@entity_name}"
        @subject += " is #{@state.upcase}" unless ['acknowledgement', 'test'].include?(@notification_type)

        begin
          fqdn       = `/bin/hostname -f`.chomp
          m_from     = "flapjack@#{fqdn}"
          @logger.debug("flapjack_mailer: set from to #{m_from}")
          m_reply_to = m_from
          m_to       = message['address']

          @logger.debug("sending Flapjack::Notification::Email " +
            "#{message['id']} to: #{m_to} subject: #{@subject}")

          mail = prepare_email(:subject  => @subject,
                  :from => m_from, :to => m_to)

          if mail.delivery_method.is_a?(::Mail::SMTP)
            mail.delivery_settings = {:address => @host, :port => @port }
          end

          mail.deliver!

          @logger.info "Email sending succeeded"

        rescue Exception => e
          @logger.error "Error delivering email to #{m_to}: #{e.message}"
          @logger.error e.backtrace.join("\n")
        end
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

