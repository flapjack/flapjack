#!/usr/bin/env ruby

require 'active_support/time'

require 'em-hiredis'

require 'flapjack/data/alert'

require 'flapjack/data/contact'
require 'flapjack/data/entity_check'
require 'flapjack/data/notification'
require 'flapjack/data/event'
require 'flapjack/redis_pool'
require 'flapjack/utility'

require 'flapjack/gateways/email'
require 'flapjack/gateways/sms_messagenet'
require 'flapjack/gateways/slack'
require 'flapjack/gateways/sms_twilio'
require 'flapjack/gateways/sms_nexmo'
require 'flapjack/gateways/aws_sns'

module Flapjack

  class Notifier

    include Flapjack::Utility

    def initialize(opts = {})
      @config = opts[:config]
      @redis_config = opts[:redis_config] || {}
      @logger = opts[:logger]
      @redis = Flapjack::RedisPool.new(:config => @redis_config, :size => 2, :logger => @logger)

      @notifications_queue = @config['queue'] || 'notifications'

      queue_configs = @config.find_all {|k, v| k =~ /_queue$/ }
      @queues = Hash[queue_configs.map {|k, v| [k[/^(.*)_queue$/, 1], v] }]

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
        exit_now!
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
        process_notification(notification) unless notification.nil?
      end

      @logger.info("Exiting main loop.")
    end

    # this must use a separate connection to the main Executive one, as it's running
    # from a different fiber while the main one is blocking.
    def stop
      @should_quit = true

      redis_uri = @redis_config[:path] ||
        "redis://#{@redis_config[:host] || '127.0.0.1'}:#{@redis_config[:port] || '6379'}/#{@redis_config[:db] || '0'}"
      shutdown_redis = EM::Hiredis.connect(redis_uri)
      shutdown_redis.rpush(@notifications_queue, Flapjack.dump_json('type' => 'shutdown'))
    end

  private

    # takes an event for which messages should be generated, works out the type of
    # notification, updates the notification history in redis, generates the
    # notifications
    def process_notification(notification)
      @logger.debug ("Processing notification: #{notification.inspect}")

      timestamp    = Time.now
      event_id     = notification.event_id
      entity_check = Flapjack::Data::EntityCheck.for_event_id(event_id,
                      :redis => @redis, :logger => @logger)
      contacts     = entity_check.contacts

      if contacts.empty?
        @logger.debug("No contacts for #{event_id}")
        @notifylog.info("#{event_id} | #{notification.type} | NO CONTACTS")
        return
      end

      messages = notification.messages(contacts,
        :default_timezone => @default_contact_timezone, :logger => @logger)

      notification_contents = notification.contents

      messages.each do |message|
        media_type = message.medium
        address    = message.address
        contents   = message.contents.merge(notification_contents)

        if message.rollup
          rollup_alerts = message.contact.alerting_checks_for_media(media_type).inject({}) do |memo, alert|
            ec = Flapjack::Data::EntityCheck.for_event_id(alert, :redis => @redis)
            last_change = ec.last_change
            memo[alert] = {
              'duration' => last_change ? (Time.now.to_i - last_change) : nil,
              'state'    => ec.state
            }
            memo
          end
          contents['rollup_alerts'] = rollup_alerts
          contents['rollup_threshold'] = message.contact.rollup_threshold_for_media(media_type)
        end

        @notifylog.info("#{event_id} | " +
          "#{notification.type} | #{message.contact.id} | #{media_type} | #{address}")

        if @queues[media_type.to_s].nil?
          @logger.error("no queue for media type: #{media_type}")
          return
        end

        @logger.info("Enqueueing #{media_type} alert for #{event_id} to #{address} type: #{notification.type} rollup: #{message.rollup || '-'}")

        contact = message.contact

        if notification.ok? || (notification.state == 'acknowledgement')
          ['warning', 'critical', 'unknown'].each do |alert_state|
            contact.update_sent_alert_keys(
              :media => media_type,
              :check => event_id,
              :state => alert_state,
              :delete => true)
          end
        else
          contact.update_sent_alert_keys(
            :media => media_type,
            :check => event_id,
            :state => notification.state)
        end

        contents_tags = contents['tags']
        contents['tags'] = contents_tags.is_a?(Set) ? contents_tags.to_a : contents_tags

        Flapjack::Data::Alert.add(@queues[media_type.to_s], contents, :redis => @redis)
      end
    end

  end
end
