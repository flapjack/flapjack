#!/usr/bin/env ruby

require 'mail'
require 'erb'
require 'haml'
require 'socket'

require 'em-synchrony'
require 'em/protocols/smtpclient'

require 'flapjack/data/entity_check'

module Flapjack
  module Gateways

    class Email

      class << self

        def pikelet_settings
          {:em_synchrony => false,
           :em_stop      => true}
        end

        def start
          @logger.info("starting")
          @logger.debug("new email gateway pikelet with the following options: #{@config.inspect}")
          @smtp_config = @config.delete('smtp_config')
          @sent = 0
        end

        def perform(notification)
          @logger.debug "Woo, got a notification to send out: #{notification.inspect}"

          @notification_type          = notification['notification_type']
          @contact_first_name         = notification['contact_first_name']
          @contact_last_name          = notification['contact_last_name']
          @state                      = notification['state']
          @summary                    = notification['summary']
          @details                    = notification['details']
          @time                       = notification['time']
          @entity_name, @check        = notification['event_id'].split(':')

          entity_check = Flapjack::Data::EntityCheck.for_event_id(notification['event_id'],
            :redis => ::Resque.redis)

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
            host = @smtp_config ? @smtp_config['host'] : nil
            port = @smtp_config ? @smtp_config['port'] : nil

            fqdn       = `/bin/hostname -f`.chomp
            m_from     = "flapjack@#{fqdn}"
            @logger.debug("flapjack_mailer: set from to #{m_from}")
            m_reply_to = m_from
            m_to       = notification['address']

          @logger.debug("sending Flapjack::Notification::Email " +
            "#{notification['id']} to: #{m_to} subject: #{@subject}")

            mail = prepare_email(:subject  => @subject,
                    :from => m_from, :to => m_to)

            email = EM::P::SmtpClient.send(
              :from     => m_from,
              :to       => m_to,
              :content  => "#{mail.to_s}\r\n.\r\n",
              :domain   => fqdn,
              :host     => host || 'localhost',
              :port     => port || 25)

            response = EM::Synchrony.sync(email)

            # http://tools.ietf.org/html/rfc821#page-36 SMTP response codes
            if response && response.respond_to?(:code) &&
              ((response.code == 250) || (response.code == 251))
              @logger.info "Email sending succeeded"
              @sent += 1
            else
              @logger.error "Email sending failed"
            end

            @logger.info "Email response: #{response.inspect}"

          rescue Exception => e
            @logger.error "Error delivering email to #{m_to}: #{e.message}"
            @logger.error e.backtrace.join("\n")
          end
        end

      end

    private

      def self.prepare_email(opts = {})

        text_template = ERB.new(File.read(File.dirname(__FILE__) +
          '/email/alert.text.erb'))

        haml_engine = Haml::Engine.new(File.read(File.dirname(__FILE__) +
          '/email/alert.html.haml'))

        mail_scope = self
        bnd = binding

        # this part is the only use of the mail gem -- maybe this can be done
        # using standard library calls instead?
        mail = Mail.new do
          from     opts[:from]
          to       opts[:to]
          subject  opts[:subject]
          reply_to opts[:from]

          text_part do
            body text_template.result(bnd)
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

