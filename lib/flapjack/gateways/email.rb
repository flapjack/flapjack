#!/usr/bin/env ruby

require 'mail'
require 'erb'
require 'socket'
require 'chronic_duration'
require 'active_support/inflector'

require 'em-synchrony'
require 'em/protocols/smtpclient'

require 'flapjack/redis_pool'
require 'flapjack/utility'

require 'flapjack/data/entity_check'
require 'flapjack/data/alert'

module Flapjack
  module Gateways

    class Email

      include Flapjack::Utility

      def initialize(opts = {})
        @config = opts[:config]
        @logger = opts[:logger]
        @redis_config = opts[:redis_config] || {}
        @redis = Flapjack::RedisPool.new(:config => @redis_config, :size => 1, :logger => @logger)

        @logger.info("starting")
        @logger.debug("new email gateway pikelet with the following options: #{@config.inspect}")
        @smtp_config = @config.delete('smtp_config')
        @sent = 0
        @fqdn = `/bin/hostname -f`.chomp
      end

      def stop
        @logger.info("stopping")
        @should_quit = true

        redis_uri = @redis_config[:path] ||
          "redis://#{@redis_config[:host] || '127.0.0.1'}:#{@redis_config[:port] || '6379'}/#{@redis_config[:db] || '0'}"
        shutdown_redis = EM::Hiredis.connect(redis_uri)
        shutdown_redis.rpush(@config['queue'], Flapjack.dump_json('notification_type' => 'shutdown'))
      end

      def start
        queue = @config['queue']

        until @should_quit
          begin
            @logger.debug("email gateway is going into blpop mode on #{queue}")
            alert = Flapjack::Data::Alert.next(queue, :redis => @redis, :logger => @logger)
            deliver(alert) unless alert.nil?
          rescue => e
            @logger.error "Error generating or dispatching email message: #{e.class}: #{e.message}\n" +
              e.backtrace.join("\n")

            # Sleep 1-2 seconds to avoid pathologically reconnecting to Redis. (Issues/866)
            # Random delay is intended as cheap stampeding herd mitigation
            sleep(1 + rand())
          end
        end
      end

      def deliver(alert)
        host = @smtp_config ? @smtp_config['host'] : nil
        port = @smtp_config ? @smtp_config['port'] : nil
        starttls = @smtp_config ? !! @smtp_config['starttls'] : nil
        m_from = @smtp_config ? @smtp_config['from'] : "flapjack@#{@fqdn}"
        m_reply_to = @smtp_config ? ( @smtp_config['reply_to'] ||= m_from ) : "flapjack@#{@fqdn}"
        if @smtp_config
          if auth_config = @smtp_config['auth']
            auth = {}
            auth[:type]     = auth_config['type'].to_sym || :plain
            auth[:username] = auth_config['username']
            auth[:password] = auth_config['password']
          end
        end

        @logger.debug("flapjack_mailer: set from to #{m_from}")

        mail = prepare_email(:from       => m_from,
                             :reply_to   => m_reply_to,
                             :to         => alert.address,
                             :message_id => "<#{alert.notification_id}@#{@fqdn}>",
                             :alert      => alert)

        smtp_from = m_from.clone
        while smtp_from =~ /(<|>)/
          smtp_from.sub!(/^.*</, '')
          smtp_from.sub!(/>.*$/, '')
        end

        smtp_args = {:from     => smtp_from,
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
        reply_to   = opts[:reply_to]
        to         = opts[:to]
        message_id = opts[:message_id]
        alert      = opts[:alert]

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

        @alert  = alert
        bnd     = binding

        # do some intelligence gathering in case an ERB execution blows up
        begin
          erb_to_be_executed = subject_template
          subject = subject_template_erb.result(bnd).chomp

          erb_to_be_executed = text_template
          body_text = text_template_erb.result(bnd)

          erb_to_be_executed = html_template
          body_html = html_template_erb.result(bnd)
        rescue => e
          @logger.error "Error while executing ERBs for an email: " +
            "ERB being executed: #{erb_to_be_executed}"
          raise
        end

        @logger.debug("preparing email to: #{to}, subject: #{subject}, message-id: #{message_id}")

        mail = Mail.new do
          from       from
          to         to
          subject    subject
          reply_to   reply_to
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
