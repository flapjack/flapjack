#!/usr/bin/env ruby

require 'mail'
require 'erb'
require 'socket'
require 'chronic_duration'
require 'active_support/inflector'

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
          @fqdn = `/bin/hostname -f`.chomp
        end

        # TODO refactor to remove complexity
        def perform(notification)
          prepare( notification )
          deliver( notification )
        end

        # sets a bunch of class instance variables for each email
        def prepare(notification)
          @logger.debug "Woo, got a notification to send out: #{notification.inspect}"

          # The instance variables are referenced by the templates, which
          # share the current binding context
          @notification_type   = notification['notification_type']
          @notification_id     = notification['id'] || SecureRandom.uuid
          @rollup              = notification['rollup']
          @rollup_alerts       = notification['rollup_alerts']
          @rollup_threshold    = notification['rollup_threshold']
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

          m_from = "flapjack@#{@fqdn}"
          @logger.debug("flapjack_mailer: set from to #{m_from}")
          m_reply_to = m_from
          m_to       = notification['address']


          mail = prepare_email(:from => m_from,
                               :to   => m_to)

          smtp_args = {:from     => m_from,
                       :to       => m_to,
                       :content  => "#{mail.to_s}\r\n.\r\n",
                       :domain   => @fqdn,
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
            "/email/#{message_type}.subject.erb"), nil, '-')

          text_template = ERB.new(File.read(File.dirname(__FILE__) +
            "/email/#{message_type}.text.erb"), nil, '-')

          html_template = ERB.new(File.read(File.dirname(__FILE__) +
            "/email/#{message_type}.html.erb"), nil, '-')

          bnd        = binding
          subject    = subject_template.result(bnd).chomp

          @logger.debug("preparing email to: #{to}, subject: #{subject}, message-id: #{message_id}")

          mail = Mail.new do
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
end

