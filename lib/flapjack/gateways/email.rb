#!/usr/bin/env ruby

require 'mail'
require 'erb'
require 'socket'
require 'chronic_duration'

require 'em-synchrony'
require 'em/protocols/smtpclient'

require 'flapjack/utility'

require 'flapjack/data/entity_check'

module Flapjack
  module Gateways

    class Email

      class << self

        include Flapjack::Utility

        def start
          @logger.info("starting")
          @logger.debug("new email gateway pikelet with the following options: #{@config.inspect}")
          @smtp_config = @config.delete('smtp_config')
          @sent = 0
        end

        # TODO refactor to remove complexity
        def perform(notification)
          prepare( notification )
          deliver( notification )
        end

        def prepare(notification)
          @logger.debug "Woo, got a notification to send out: #{notification.inspect}"

          # The instance variables are referenced by the templates, which
          # share the current binding context
          @notification_type   = notification['notification_type']
          @contact_first_name  = notification['contact_first_name']
          @contact_last_name   = notification['contact_last_name']
          @state               = notification['state']
          @duration            = notification['state_duration']
          @summary             = notification['summary']
          @last_state          = notification['last_state']
          @last_summary        = notification['last_summary']
          @details             = notification['details']
          @time                = notification['time']
          @entity_name, @check = notification['event_id'].split(':', 2)

          entity_check = Flapjack::Data::EntityCheck.for_event_id(notification['event_id'],
            :redis => @redis)

          @in_unscheduled_maintenance = entity_check.in_scheduled_maintenance?
          @in_scheduled_maintenance   = entity_check.in_unscheduled_maintenance?

          if lc = entity_check.last_change
            @duration  = Time.now.to_i - lc
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
        rescue => e
          @logger.error "Error preparing email to #{m_to}: #{e.class}: #{e.message}"
          @logger.error e.backtrace.join("\n")
          raise
        end

        def deliver(notification)
          host = @smtp_config ? @smtp_config['host'] : nil
          port = @smtp_config ? @smtp_config['port'] : nil
          starttls = @smtp_config ? !! @smtp_config['starttls'] : nil
          if @smtp_config
            if auth_config = @smtp_config['auth']
              auth = {}
              auth[:type]     = auth_config['type'].to_sym || :plain
              auth[:username] = auth_config['username']
              auth[:password] = auth_config['password']
            end
          end

          fqdn = `/bin/hostname -f`.chomp
          m_from = "flapjack@#{fqdn}"
          @logger.debug("flapjack_mailer: set from to #{m_from}")
          m_reply_to = m_from
          m_to       = notification['address']

          @logger.debug("sending Flapjack::Notification::Email " +
            "#{notification['id']} to: #{m_to} subject: #{@subject}")

          mail = prepare_email(:subject => @subject,
                               :from    => m_from,
                               :to => m_to)

          smtp_args = {:from     => m_from,
                       :to       => m_to,
                       :content  => "#{mail.to_s}\r\n.\r\n",
                       :domain   => fqdn,
                       :host     => host || 'localhost',
                       :port     => port || 25,
                       :starttls => starttls}
          smtp_args.merge!(:auth => auth) if auth
          email = EM::P::SmtpClient.send(smtp_args)

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

        rescue => e
          @logger.error "Error delivering email to #{m_to}: #{e.class}: #{e.message}"
          @logger.error e.backtrace.join("\n")
          raise
        end

        private

        def prepare_email(opts = {})

          text_template = ERB.new(File.read(File.dirname(__FILE__) +
            '/email/alert.text.erb'), nil, '-')

          html_template = ERB.new(File.read(File.dirname(__FILE__) +
            '/email/alert.html.erb'), nil, '-')

          bnd = binding

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
              body html_template.result(bnd)
            end
          end

        end
      end

    end
  end
end

