#!/usr/bin/env ruby

require 'active_support/time'

require 'oj'

require 'flapjack/redis_proxy'

require 'flapjack/data/contact'
require 'flapjack/data/check'
require 'flapjack/data/notification'
require 'flapjack/data/event'

require 'flapjack/exceptions'
require 'flapjack/utility'

module Flapjack

  class Notifier

    include Flapjack::Utility

    def initialize(opts = {})
      @lock = opts[:lock]
      @config = opts[:config] || {}
      @logger = opts[:logger]

      @notifications_queue = @config['queue'] || 'notifications'

      @queues = {:email     => (@config['email_queue']     || 'email_notifications'),
                 :sms       => (@config['sms_queue']       || 'sms_notifications'),
                 :jabber    => (@config['jabber_queue']    || 'jabber_notifications'),
                 :pagerduty => (@config['pagerduty_queue'] || 'pagerduty_notifications')
                }

      notify_logfile  = @config['notification_log_file'] || 'log/notify.log'
      unless File.directory?(File.dirname(notify_logfile))
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
        tz = ActiveSupport::TimeZone.new(tz_string.untaint)
      rescue ArgumentError
        logger.error("Invalid timezone string specified in default_contact_timezone or TZ (#{tz_string})")
        exit 1
      end
      @default_contact_timezone = tz
    end

    def start
      begin
        loop do
          @lock.synchronize do
            foreach_on_queue {|notif| process_notification(notif) }
          end

          wait_for_queue
        end
      ensure
        Flapjack.redis.quit
      end
    end

    def stop_type
      :exception
    end

  private

    def foreach_on_queue
      while notif_json = Flapjack.redis.rpop(@notifications_queue)
        begin
          notification = ::Oj.load( notif_json )
        rescue Oj::Error => e
          @logger.warn("Error deserialising notification json: #{e}, raw json: #{notif_json.inspect}")
          notification = nil
        end

        next unless notification

        # TODO tags must be a Set -- convert, or ease that restriction
        symbolized_notification = notification.inject({}) {|m,(k,v)| m[k.to_sym] = v; m}
        yield Flapjack::Data::Notification.new(symbolized_notification) if block_given?
      end
    end

    def wait_for_queue
      Flapjack.redis.brpop("#{@notifications_queue}_actions")
    end

    # takes an event for which messages should be generated, works out the type of
    # notification, updates the notification history in redis, generates the
    # notifications
    def process_notification(notification)
      @logger.debug ("Processing notification: #{notification.inspect}")

      timestamp       = Time.now
      entity_check_id = notification.entity_check_id
      entity_check    = Flapjack::Data::Check.find_by_id(entity_check_id)
      contacts        = entity_check.contacts.all + entity_check.entity.contacts.all

      if contacts.empty?
        @logger.debug("No contacts for '#{entity_check.entity_name}:#{entity_check.name}'")
        @notifylog.info("#{entity_check.entity_name}:#{entity_check.name} | #{notification.type} | NO CONTACTS")
        return
      end

      messages = notification.messages(contacts,
        :default_timezone => @default_contact_timezone,
        :logger => @logger)

      notification_contents = notification.contents

      in_unscheduled_maintenance = entity_check.in_scheduled_maintenance?
      in_scheduled_maintenance   = entity_check.in_unscheduled_maintenance?

      messages.each do |message|
        media_type = message.medium
        unless @queues.keys.include?(media_type.to_sym)
          @logger.error("no queue for media type: #{media_type}")
          next
        end

        medium = message.contact.media.intersect(:type => media_type).all.first
        if medium.nil?
          @logger.warning("contact has no media for type: #{media_type}")
          next
        end

        address = message.address

        @notifylog.info("#{entity_check.entity_name}:#{entity_check.name} | " +
          "#{notification.type} | #{message.contact.id} | #{media_type} | #{address}")

        @logger.info("Enqueueing #{media_type} alert for " +
          "#{entity_check.entity_name}:#{entity_check.name} to #{address} " +
          " type: #{notification.type} rollup: #{message.rollup || '-'}")

        contents   = message.contents.merge(notification_contents)
        contents['rollup_alerts'] = medium.alerting_checks.all.inject({}) do |memo, entity_check|
          last_state  = entity_check.states.last
          last_change = last_state.nil? ? nil : last_state.timestamp.to_i
          memo["#{entity_check.entity_name}:#{entity_check.name}"] = {
            'duration' => (last_change ? (Time.now.to_i - last_change) : nil),
            'state'    => (last_state ? last_state.state : nil),
          }
          memo
        end
        contents['rollup_threshold'] = medium.rollup_threshold

        contents_tags = contents['tags']
        contents['tags'] = contents_tags.is_a?(Set) ? contents_tags.to_a : contents_tags

        if ['recovery', 'acknowledgement'].include?(notification.type)

          ['warning', 'critical', 'unknown'].each do |alert_state|
            medium.update_sent_alert_keys(
              :entity_check => entity_check,
              :state => alert_state,
              :delete => true)
          end
        elsif notification.state
          medium.update_sent_alert_keys(
            :entity_check => entity_check,
            :state => notification.state.state)
        end

        Flapjack::Data::Message.push(@queues[media_type.to_sym], contents)
      end
    end

  end
end
