#!/usr/bin/env ruby

require 'mail'
require 'erb'
require 'haml'
require 'socket'

require 'flapjack/pikelet'
require 'flapjack/data/entity_check'

module Flapjack
  module Notification

    class Email

      extend Flapjack::ResquePikelet

      class << self

        alias_method :orig_bootstrap, :bootstrap

        # See https://github.com/mikel/mail/blob/master/lib/mail/mail.rb#L53
        # & https://github.com/mikel/mail/blob/master/spec/mail/configuration_spec.rb
        # for details of configuring mail gem. defaults to SMTP, localhost, port 25
        def bootstrap(opts = {})
          return if @bootstrapped

          sc = opts[:config].delete('smtp_config')

          if sc
            smtp_config = sc.keys.inject({}) do |ret,obj|
                ret[obj.to_sym] = sc[obj]
                ret
            end

            Mail.defaults {
              delivery_method :smtp, {:enable_starttls_auto => false}.merge(smtp_config)
            }
          end
          orig_bootstrap(opts)
        end

        def perform(notification)
          @logger.debug "Woo, got a notification to send out: #{notification.inspect}"
          opts = {:logger => @logger}

          notification_type  = notification['notification_type']
          contact_first_name = notification['contact_first_name']
          contact_last_name  = notification['contact_last_name']
          state              = notification['state']
          summary            = notification['summary']
          time               = notification['time']
          entity, check      = notification['event_id'].split(':')

          entity_check = Flapjack::Data::EntityCheck.for_event_id(notification['event_id'],
            :redis => ::Resque.redis)

          headline_map = {'problem'         => 'Problem: ',
                          'recovery'        => 'Recovery: ',
                          'acknowledgement' => 'Acknowledgement: ',
                          'test'            => 'Test Notification: ',
                          'unknown'         => ''
                         }

          headline = headline_map[notification_type] || ''

          subject = "#{headline}'#{check}' on #{entity}"
          subject += " is #{state.upcase}" unless ['acknowledgement', 'test'].include?(notification_type)

          notification['subject'] = subject

          mail = prepare_email(notification, :logger => @logger,
                  :in_scheduled_maintenance   => entity_check.in_scheduled_maintenance?,
                  :in_unscheduled_maintenance => entity_check.in_unscheduled_maintenance?)
          mail.deliver!
        end

      end

    private

      def self.prepare_email(notification, opts)

        logger = opts[:logger]

        # not using socket and gethostname as that doesn't give you a fqdn.
        # see the facter issue: https://projects.puppetlabs.com/issues/3898
        fqdn       = `/bin/hostname -f`.chomp
        m_from     = "flapjack@#{fqdn}"
        logger.debug("flapjack_mailer: set from to #{m_from}")
        m_reply_to = m_from

        m_to       = notification['address']
        m_subject  = notification['subject']

        logger.debug("sending Flapjack::Notification::Email " +
          "#{notification['id']} to: #{m_to} subject: #{m_subject}")

        @notification_type  = notification['notification_type']
        @contact_first_name = notification['contact_first_name']
        @contact_last_name  = notification['contact_last_name']
        @state              = notification['state']
        @summary            = notification['summary']
        @time               = notification['time']
        @entity, @check     = notification['event_id'].split(':')
        @in_unscheduled_maintenance = opts[:in_unscheduled_maintenance]
        @in_scheduled_maintenance   = opts[:in_scheduled_maintenance]

        text_template = ERB.new(File.read(File.dirname(__FILE__) +
          '/email/alert.text.erb'))

        haml_engine = Haml::Engine.new(File.read(File.dirname(__FILE__) +
          '/email/alert.html.haml'))

        mail_scope = self

        mail = Mail.new do
          from     m_from
          to       m_to
          subject  m_subject
          reply_to m_reply_to

          text_part do
            body text_template.result(binding)
          end

          html_part do
            content_type 'text/html; charset=UTF-8'
            body haml_engine.render(mail_scope)
          end
        end
      end

    end
  end
end

