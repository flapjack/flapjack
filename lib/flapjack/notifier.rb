#!/usr/bin/env ruby

require 'log4r'
require 'log4r/outputter/fileoutputter'
require 'active_support/time'

require 'yajl/json_gem'

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
      @redis_config = opts[:redis_config]
      @logger = opts[:logger]
      @redis = Flapjack::RedisPool.new(:config => @redis_config, :size => 2) # first will block

      # TODO load executive config fields first, for backwards compatability
      # (probably do this in coordinator)
      @notifications_queue = @config['queue'] || 'notifications'

      @queues = {:email     => @config['email_queue'],
                 :sms       => @config['sms_queue'],
                 :jabber    => @config['jabber_queue'],
                 :pagerduty => @config['pagerduty_queue']}

      notifylog  = @config['notification_log_file'] || 'log/notify.log'
      if not File.directory?(File.dirname(notifylog))
        puts "Parent directory for log file #{notifylog} doesn't exist"
        puts "Exiting!"
        exit
      end
      @notifylog = Log4r::Logger.new("notifier")
      @notifylog.add(Log4r::FileOutputter.new("notifylog", :filename => notifylog))

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
      @redis.rpush(@notifications_queue, JSON.generate('type' => 'shutdown'))
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
        @notifylog.info("#{timestamp.to_s} | #{event_id} | #{notification_type} | NO CONTACTS")
        return
      end

      messages = notification.messages(contacts, :default_timezone => @default_contact_timezone,
        :logger => @logger)

      notification_contents = notification.contents

      messages.each do |message|
        media_type = message.medium
        address    = message.address
        contents   = message.contents.merge(notification_contents)

        @notifylog.info("#{timestamp.to_s} | #{event_id} | " +
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
          @redis.rpush(@queues[:jabber], Yajl::Encoder.encode(contents))
        when :pagerduty
          @redis.rpush(@queues[:pagerduty], Yajl::Encoder.encode(contents))
        end
      end
    end

  end
end
