#!/usr/bin/env ruby

require 'mail'
require 'erb'
require 'haml'

require 'flapjack/data/entity_check'
require 'flapjack/notification/common'

module Flapjack
  module Notification

    class Email
      extend Flapjack::Notification::Common

      def self.dispatch(notification, opts = {})
        notification_type  = notification['notification_type']
        contact_first_name = notification['contact_first_name']
        contact_last_name  = notification['contact_last_name']
        state              = notification['state']
        summary            = notification['summary']
        time               = notification['time']
        entity, check      = notification['event_id'].split(':')

        entity_check = Flapjack::Data::EntityCheck.for_event_id(notification['event_id'],
          :redis => opts[:redis])

        headline_map = {'problem'         => 'Problem: ',
                        'recovery'        => 'Recovery: ',
                        'acknowledgement' => 'Acknowledgement: ',
                        'unknown'         => ''
                       }

        headline = headline_map[notification_type] || ''

        subject = "#{headline}'#{check}' on #{entity}"
        subject += " is #{state.upcase}" unless notification_type == 'acknowledgement'

        notification['subject'] = subject
        opts[:logger].debug "Flapjack::Notification::Email#dispatch is calling Flapjack::Notification::Mailer.sender, notification_id: #{notification['id']}"
        sender_opts = {:logger => opts[:logger],
                       :in_scheduled_maintenance   => entity_check.in_scheduled_maintenance?,
                       :in_unscheduled_maintenance => entity_check.in_unscheduled_maintenance?
                      }

        mail = prepare_email(notification, sender_opts)
        mail.deliver!
      end

    private

      def self.prepare_email(notification, opts)

        logger = opts[:logger]

        # FIXME: use socket and gethostname instead of shelling out
        fqdn     = `/bin/hostname -f`.chomp
        m_from     = "flapjack@#{fqdn}"
        logger.debug("flapjack_mailer: set from to #{m_from}")
        m_reply_to = m_from

        m_to       = notification['address']
        m_subject  = notification['subject']

        logger.debug("Flapjack::Notification::Mailer #{notification['id']} to: #{m_to} subject: #{m_subject}")

        @notification_type  = notification['notification_type']
        @contact_first_name = notification['contact_first_name']
        @contact_last_name  = notification['contact_last_name']
        @state              = notification['state']
        @summary            = notification['summary']
        @time               = notification['time']
        @entity, @check     = notification['event_id'].split(':')
        @in_unscheduled_maintenance = opts[:in_unscheduled_maintenance]
        @in_scheduled_maintenance   = opts[:in_scheduled_maintenance]

        mail_scope = self

        mail = Mail.new do
          from     m_from
          to       m_to
          subject  m_subject
          reply_to m_reply_to

          text_part do
            template = ERB.new(File.read(File.dirname(__FILE__) +
              '/flapjack_mailer/sender.text.erb'))
            template.result(binding)
          end

          html_part do
            engine = Haml::Engine.new(File.read(File.dirname(__FILE__) +
          '/flapjack_mailer/sender.html.haml'))
            engine.render(mail_scope)
          end
        end
      end

    end
  end
end

