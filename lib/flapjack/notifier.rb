#!/usr/bin/env ruby

require 'active_support/time'

require 'oj'

require 'flapjack/exceptions'
require 'flapjack/redis_proxy'
require 'flapjack/record_queue'
require 'flapjack/utility'

require 'flapjack/data/alert'
require 'flapjack/data/check'
require 'flapjack/data/contact'
require 'flapjack/data/event'
require 'flapjack/data/notification'
require 'flapjack/data/rollup_alert'

module Flapjack

  class Notifier

    include Flapjack::Utility

    def initialize(opts = {})
      @lock = opts[:lock]
      @config = opts[:config] || {}
      @logger = opts[:logger]

      @queue = Flapjack::RecordQueue.new(@config['queue'] || 'notifications',
                 Flapjack::Data::Notification)

      queue_configs = @config.find_all {|k, v| k =~ /_queue$/ }
      @queues = Hash[queue_configs.map {|k, v|
        [k[/^(.*)_queue$/, 1], Flapjack::RecordQueue.new(v, Flapjack::Data::Alert)]
      }]

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
        Sandstorm.redis = Flapjack.redis

        loop do
          @lock.synchronize do
            @queue.foreach {|notif| process_notification(notif) }
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

    # takes an event for which messages should be generated, works out the type of
    # notification, updates the notification history in redis, generates the
    # notifications
    def process_notification(notification)
      @logger.debug ("Processing notification: #{notification.inspect}")

      timestamp   = Time.now
      check       = notification.check
      contacts    = check.contacts.all + check.entity.contacts.all

      check_name  = check.name
      entity_name = check.entity.name

      if contacts.empty?
        @logger.debug("No contacts for '#{entity_name}:#{check_name}'")
        @notifylog.info("#{entity_name}:#{check_name} | #{notification.type} | NO CONTACTS")
        return
      end

      alerts = notification.alerts(contacts,
        :default_timezone => @default_contact_timezone,
        :logger => @logger)

      in_unscheduled_maintenance = check.in_scheduled_maintenance?
      in_scheduled_maintenance   = check.in_unscheduled_maintenance?

      alerts.each do |alert|
        medium = alert.medium
        unless @queues.has_key?(medium.type)
          @logger.error("no queue for media type: #{medium.type}")
          next
        end

        address = medium.address

        @notifylog.info("#{entity_name}:#{check_name} | " +
          "#{notification.type} | #{medium.contact.id} | #{medium.type} | #{medium.address}")

        @logger.info("Enqueueing #{medium.type} alert for " +
          "#{entity_name}:#{check_name} to #{medium.address} " +
          " type: #{notification.type} rollup: #{alert.rollup || '-'}")

        Flapjack::Data::Check.backend.lock(Flapjack::Data::Check,
          Flapjack::Data::CheckState, Flapjack::Data::Alert,
          Flapjack::Data::RollupAlert) do

          medium.alerting_checks.each do |alert_check|
            last_state  = alert_check.states.last
            last_change = last_state.nil? ? nil : last_state.timestamp.to_i

            rollup_alert = Flapjack::Data::RollupAlert.new(
              :state    => (last_state ? last_state.state : nil),
              :duration => (last_change ? (Time.now.to_i - last_change) : nil))
            rollup_alert.save
            alert.rollup_alerts << rollup_alert
            alert_check.rollup_alerts << rollup_alert
          end

        end

        if ['recovery', 'acknowledgement'].include?(notification.type)

          ['warning', 'critical', 'unknown'].each do |alert_state|
            medium.update_sent_alert_keys(
              :check => check,
              :state => alert_state,
              :delete => true)
          end
        elsif notification.state
          medium.update_sent_alert_keys(
            :check => check,
            :state => notification.state.state)
        end

        # # Alert tags aren't set properly, I think
        # contents_tags = contents['tags']
        # contents['tags'] = contents_tags.is_a?(Set) ? contents_tags.to_a : contents_tags

        @queues[medium.type].push(alert)
      end
    end

  end
end
