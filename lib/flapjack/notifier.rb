#!/usr/bin/env ruby

require 'active_support/time'

require 'oj'

require 'flapjack/data/contact'
require 'flapjack/data/entity_check'
require 'flapjack/data/notification'
require 'flapjack/data/event'
require 'flapjack/redis_pool'
require 'flapjack/utility'

require 'flapjack/gateways/email'
require 'flapjack/gateways/sms_messagenet'

module Flapjack

  class Notifier

    include Flapjack::Utility

    def initialize(opts = {})
      @config = opts[:config]
      @redis_config = opts[:redis_config] || {}
      @logger = opts[:logger]
      @redis = Flapjack::RedisPool.new(:config => @redis_config, :size => 1)

      @notifications_queue = @config['queue'] || 'notifications'

      @queues = {:email     => @config['email_queue'],
                 :sms       => @config['sms_queue'],
                 :jabber    => @config['jabber_queue'],
                 :pagerduty => @config['pagerduty_queue']}

      notify_logfile  = @config['notification_log_file'] || 'log/notify.log'
      if not File.directory?(File.dirname(notify_logfile))
        puts "Parent directory for log file '#{notify_logfile}' doesn't exist"
        puts "Exiting!"
        exit
      end
      @notifylog = ::Logger.new(notify_logfile)
      @notifylog.formatter = proc do |severity, datetime, progname, msg|
        "#{datetime.to_s} | #{msg}\n"
      end

      tz = nil
      tz_string = @config['default_contact_timezone'] || ENV['TZ'] || 'UTC'
      begin
        tz = ActiveSupport::TimeZone.new(tz_string)
      rescue ArgumentError
        logger.error("Invalid timezone string specified in default_contact_timezone or TZ (#{tz_string})")
        exit 1
      end
      @default_contact_timezone = tz
    end

    def start
      @logger.info("Booting main loop.")

      until @should_quit
        @logger.debug("Waiting for notification...")
        notification = Flapjack::Data::Notification.next(@notifications_queue,
                                                         :redis => @redis,
                                                         :logger => @logger)
        process_notification(notification) unless notification.nil? || (notification.type == 'shutdown')
      end

      @logger.info("Exiting main loop.")
    end

    # this must use a separate connection to the main Executive one, as it's running
    # from a different fiber while the main one is blocking.
    def stop
      @should_quit = true
      shutdown_redis = Redis.new(@redis_config.merge(:driver => :hiredis))
      shutdown_redis.rpush(@notifications_queue, Oj.dump('type' => 'shutdown'))
    end

  private

    # takes an event for which messages should be generated, works out the type of
    # notification, updates the notification history in redis, generates the
    # notifications
    def process_notification(notification)
      timestamp = Time.now
      event_id = notification.event_id
      entity_check = Flapjack::Data::EntityCheck.for_event_id(event_id, :redis => @redis)
      contacts = entity_check.contacts

      if contacts.empty?
        @logger.debug("No contacts for #{event_id}")
        @notifylog.info("#{event_id} | #{notification.type} | NO CONTACTS")
        return
      end

      messages = notification.messages(contacts, :default_timezone => @default_contact_timezone,
        :logger => @logger)

      notification_contents = notification.contents

      messages.each do |message|
        media_type = message.medium
        address    = message.address
        contents   = message.contents.merge(notification_contents)

        @notifylog.info("#{event_id} | " +
          "#{notification.type} | #{message.contact.id} | #{media_type} | #{address}")

        unless @queues[media_type.to_sym]
          @logger.error("no queue for media type: #{media_type}")
          return
        end

        @logger.info("Enqueueing #{media_type} alert for #{event_id} to #{address}")

        contact = message.contact

        # was event.ok?
        if (notification.event_state == 'ok') || (notification.event_state == 'up')
          contact.update_sent_alert_keys(
            :media => media_type,
            :check => event_id,
            :state => 'warning',
            :delete => true)
          contact.update_sent_alert_keys(
            :media => media_type,
            :check => event_id,
            :state => 'critical',
            :delete => true)
          contact.update_sent_alert_keys(
            :media => media_type,
            :check => event_id,
            :state => 'unknown',
            :delete => true)
        else
          contact.update_sent_alert_keys(
            :media => media_type,
            :check => event_id,
            :state => notification.event_state)
        end

        # TODO consider changing Resque jobs to use raw blpop like the others
        case media_type.to_sym
        when :sms
          Resque.enqueue_to(@queues[:sms], Flapjack::Gateways::SmsMessagenet, contents)
        when :email
          Resque.enqueue_to(@queues[:email], Flapjack::Gateways::Email, contents)
        when :jabber
          @redis.rpush(@queues[:jabber], Oj.dump(contents))
        when :pagerduty
          @redis.rpush(@queues[:pagerduty], Oj.dump(contents))
        end
      end
    end

  end
end
