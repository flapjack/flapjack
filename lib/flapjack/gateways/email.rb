#!/usr/bin/env ruby

require 'mail'
require 'erb'
require 'socket'
require 'chronic_duration'
require 'active_support/inflector'

require 'flapjack/redis_proxy'
require 'flapjack/record_queue'
require 'flapjack/utility'
require 'flapjack/exceptions'

require 'flapjack/data/alert'
require 'flapjack/data/check'

module Flapjack
  module Gateways

    class Email

      include Flapjack::Utility

      attr_accessor :sent

      def initialize(opts = {})
        @lock = opts[:lock]
        @config = opts[:config]
        @logger = opts[:logger]

        # TODO support for config reloading
        @queue = Flapjack::RecordQueue.new(@config['queue'] || 'email_notifications',
                   Flapjack::Data::Alert)

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

        @fqdn = `/bin/hostname -f`.chomp
        @sent = 0
      end

      def start
        @logger.debug("new email gateway pikelet with the following options: #{@config.inspect}")

        begin
          loop do
            @lock.synchronize do
              @queue.foreach {|alert| handle_alert(alert) }
            end

            @queue.wait
          end
        ensure
          Flapjack.redis.quit
        end
      end

      def stop_type
        :exception
      end

      private

      def handle_alert(alert)
        @logger.debug "Woo, got an alert to send out: #{alert.inspect}"
        host = @smtp_config ? @smtp_config['host'] : nil
        port = @smtp_config ? @smtp_config['port'] : nil
        starttls = @smtp_config ? !! @smtp_config['starttls'] : nil
        if @smtp_config
          if auth_config = @smtp_config['auth']
            auth = {}
            auth[:type] = auth_config['type'].to_sym || :plain
            auth[:username] = auth_config['username']
            auth[:password] = auth_config['password']
          end
        end

        m_from = "flapjack@#{@fqdn}"
        @logger.debug("flapjack_mailer: set from to #{m_from}")

        mail = prepare_email(:from => m_from,
                             :to => alert.medium.address,
                             :message_id => "<#{alert.id}@#{@fqdn}>",
                             :alert => alert)

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
      rescue => e
        @logger.error "Error generating or delivering email to #{alert.medium.address}: #{e.class}: #{e.message}"
        @logger.error e.backtrace.join("\n")
        raise
      end

      # returns a Mail object
      def prepare_email(opts = {})
        from = opts[:from]
        to = opts[:to]
        message_id = opts[:message_id]
        alert = opts[:alert]

        message_type = case
        when alert.rollup
          'rollup'
        else
          'alert'
        end

        mydir = File.dirname(__FILE__)

        subject_template_path = mydir + "/email/#{message_type}_subject.text.erb"
        text_template_path = mydir + "/email/#{message_type}.text.erb"
        html_template_path = mydir + "/email/#{message_type}.html.erb"

        subject_template = ERB.new(File.read(subject_template_path), nil, '-')
        text_template = ERB.new(File.read(text_template_path), nil, '-')
        html_template = ERB.new(File.read(html_template_path), nil, '-')

        @alert = alert
        bnd = binding

        # do some intelligence gathering in case an ERB execution blows up
        begin
          erb_to_be_executed = subject_template_path
          subject = subject_template.result(bnd).chomp

          erb_to_be_executed = text_template_path
          body_text = text_template.result(bnd)

          erb_to_be_executed = html_template_path
          body_html = html_template.result(bnd)
        rescue => e
          @logger.error "Error while executing ERBs for an email: " +
            "ERB being executed: #{erb_to_be_executed}"
          raise
        end

        @logger.debug("preparing email to: #{to}, subject: #{subject}, message-id: #{message_id}")

        mail = Mail.new do
          from from
          to to
          subject subject
          reply_to from
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

