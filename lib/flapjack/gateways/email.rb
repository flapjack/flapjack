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
require 'flapjack/data/alert'

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
        def perform(contents)
          @logger.debug "Woo, got an alert to send out: #{contents.inspect}"
          alert = prepare(contents)
          deliver(alert)
        end

        # sets a bunch of class instance variables for each email
        def prepare(contents)
          Flapjack::Data::Alert.new(contents, :logger => @logger)
        rescue => e
          @logger.error "Error preparing email to #{contents['address']}: #{e.class}: #{e.message}"
          @logger.error e.backtrace.join("\n")
          raise
        end

        def deliver(alert)
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

          mail = prepare_email(:from       => m_from,
                               :to         => alert.address,
                               :message_id => "<#{alert.notification_id}@#{@fqdn}>",
                               :alert      => alert)

          smtp_args = {:from     => m_from,
                       :to       => alert.address,
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
            alert.record_send_success!
            @sent += 1
          else
            @logger.error "Email sending failed"
          end

          @logger.debug "Email response: #{response.inspect}"

        rescue => e
          @logger.error "Error generating or delivering email to #{alert.address}: #{e.class}: #{e.message}"
          @logger.error e.backtrace.join("\n")
          raise
        end

        private

        # returns a Mail object
        def prepare_email(opts = {})
          from       = opts[:from]
          to         = opts[:to]
          message_id = opts[:message_id]
          alert      = opts[:alert]

          message_type = case
          when alert.rollup
            'rollup'
          else
            'alert'
          end

          mydir = File.dirname(__FILE__)

          subject_template_path = mydir + "/email/#{message_type}_subject.text.erb"
          text_template_path    = mydir + "/email/#{message_type}.text.erb"
          html_template_path    = mydir + "/email/#{message_type}.html.erb"

          subject_template = ERB.new(File.read(subject_template_path), nil, '-')
          text_template    = ERB.new(File.read(text_template_path), nil, '-')
          html_template    = ERB.new(File.read(html_template_path), nil, '-')

          @alert  = alert
          bnd     = binding

          # do some intelligence gathering in case an ERB execution blows up
          begin
            erb_to_be_executed = subject_template_path
            subject = subject_template.result(bnd).chomp

            erb_to_be_executed = text_template_path
            body_text = text_template.result(bnd)

            erb_to_be_executed = html_template_path
            body_html = html_template.result(bnd)
          rescue => e
            @logger.error "Error while excuting ERBs for an email: " +
              "ERB being executed: #{erb_to_be_executed}"
            raise
          end

          @logger.debug("preparing email to: #{to}, subject: #{subject}, message-id: #{message_id}")

          mail = Mail.new do
            from       from
            to         to
            subject    subject
            reply_to   from
            message_id message_id

            text_part do
              body body_text
            end

            html_part do
              content_type 'text/html; charset=UTF-8'
              body body_html
            end
          end

        end
      end

    end
  end
end

