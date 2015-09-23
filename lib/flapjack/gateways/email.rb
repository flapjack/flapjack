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
require 'flapjack/data/contact'

module Flapjack
  module Gateways

    class Email

      include Flapjack::Utility

      attr_accessor :sent

      def initialize(opts = {})
        @lock = opts[:lock]
        @config = opts[:config]

        # TODO support for config reloading
        @queue = Flapjack::RecordQueue.new(@config['queue'] || 'email_notifications',
                   Flapjack::Data::Alert)

        if @smtp_config = @config['smtp_config']
          @host = @smtp_config['host'] || 'localhost'
          @port = @smtp_config['port'] || 25

          # NB: needs testing
          if @smtp_config['authentication'] && @smtp_config['username'] &&
            @smtp_config['password']

            @auth = {:authentication => @smtp_config['authentication'],
                     :username => @smtp_config['username'],
                     :password => @smtp_config['password'],
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
        Flapjack.logger.debug("new email gateway pikelet with the following options: #{@config.inspect}")

        begin
          Zermelo.redis = Flapjack.redis

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

      def safe_address(addr)
        return "flapjack@#{@fqdn}" if addr.nil? || addr.empty?
        safe_addr = addr.clone
        while safe_addr =~ /(<|>)/
          safe_addr.sub!(/^.*</, '').sub!(/>.*$/, '')
        end

        safe_addr
      end

      def handle_alert(alert)
        Flapjack.logger.debug "Woo, got an alert to send out: #{alert.inspect}"
        if @smtp_config
          host = @smtp_config['host']
          port = @smtp_config['port']
          starttls = !!@smtp_config['starttls']

          m_from = safe_address(@smtp_config['from'])
          m_reply_to = @smtp_config['reply_to'] || @smtp_config['from']

          if auth_config = @smtp_config['auth']
            auth = {}
            auth[:type] = auth_config['type'].to_sym || :plain
            auth[:username] = auth_config['username']
            auth[:password] = auth_config['password']
          end
        else
          host = nil
          port = nil
          starttls = nil
          m_reply_to = m_from = "flapjack@#{@fqdn}"
        end

        Flapjack.logger.debug("flapjack_mailer: set from to #{m_from}")

        mail = prepare_email(:from => m_from,
                             :reply_to => m_reply_to,
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

        Flapjack.logger.info "Email sending succeeded"
        @sent += 1
      rescue => e
        Flapjack.logger.error "Error generating or delivering email to #{alert.medium.address}: #{e.class}: #{e.message}"
        Flapjack.logger.error e.backtrace.join("\n")
        raise
      end

      # returns a Mail object
      def prepare_email(opts = {})
        from = opts[:from]
        to = opts[:to]
        reply_to = opts[:reply_to]
        message_id = opts[:message_id]
        alert = opts[:alert]

        message_type = alert.rollup ? 'rollup' : 'alert'

        subject_template_erb, subject_template =
          load_template(@config['templates'], "#{message_type}_subject",
                        'text', File.join(File.dirname(__FILE__), 'email'))

        text_template_erb, text_template =
          load_template(@config['templates'], message_type,
                        'text', File.join(File.dirname(__FILE__), 'email'))

        html_template_erb, html_template =
          load_template(@config['templates'], message_type,
                        'html', File.join(File.dirname(__FILE__), 'email'))

        @alert = alert
        bnd = binding

        # do some intelligence gathering in case an ERB execution blows up
        begin
          erb_to_be_executed = subject_template
          subject = subject_template_erb.result(bnd).chomp

          erb_to_be_executed = text_template
          body_text = text_template_erb.result(bnd)

          erb_to_be_executed = html_template
          body_html = html_template_erb.result(bnd)
        rescue
          Flapjack.logger.error "Error while executing ERBs for an email: " +
            "ERB being executed: #{erb_to_be_executed}"
          raise
        end

        Flapjack.logger.debug("preparing email to: #{to}, subject: #{subject}, message-id: #{message_id}")

        Mail.new do
          from from
          to to
          subject subject
          reply_to reply_to
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
