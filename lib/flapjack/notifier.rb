#!/usr/bin/env ruby

require 'active_support/time'

require 'flapjack/exceptions'
require 'flapjack/redis_proxy'
require 'flapjack/record_queue'
require 'flapjack/utility'

require 'flapjack/data/alert'
require 'flapjack/data/check'
require 'flapjack/data/contact'
require 'flapjack/data/event'
require 'flapjack/data/notification'

module Flapjack

  class Notifier

    include Flapjack::Utility

    def initialize(opts = {})
      @lock = opts[:lock]
      @config = opts[:config] || {}

      @queue = Flapjack::RecordQueue.new(@config['queue'] || 'notifications',
                 Flapjack::Data::Notification)

      queue_configs = @config.find_all {|k, v| k =~ /_queue$/ }
      @queues = Hash[queue_configs.map {|k, v|
        [k[/^(.*)_queue$/, 1], Flapjack::RecordQueue.new(v, Flapjack::Data::Alert)]
      }]

      if @queues.empty?
        raise "No queues for media transports"
      end

      notify_logfile  = @config['notification_log_file'] || 'log/notify.log'
      unless File.directory?(File.dirname(notify_logfile))
        raise "Parent directory for log file '#{notify_logfile}' doesn't exist"
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
        raise "Invalid timezone string specified in default_contact_timezone or TZ (#{tz_string})"
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
      Flapjack.logger.debug ("Processing notification: #{notification.inspect}")

      check       = notification.entry.state.check
      check_name  = check.name

      rule_ids_by_contact_id = check.rule_ids_by_contact_id(:severity => notification.severity)

      if rule_ids_by_contact_id.empty?
        Flapjack.logger.debug("No rules for '#{check_name}'")
        @notifylog.info("#{check_name} | #{notification.type} | NO RULES")
        return
      end

      alerts = notification.alerts_for(rule_ids_by_contact_id,
        :transports => @queues.keys,
        :default_timezone => @default_contact_timezone)

      Flapjack.logger.info "alerts: #{alerts.size}"

      alerts.each do |alert|
        medium = alert.medium

        @notifylog.info("#{check_name} | #{medium.contact.id} | " \
                        "#{medium.transport} | #{medium.address}")

        Flapjack.logger.info("Enqueueing #{medium.transport} alert for " +
          "#{check_name} to #{medium.address} " +
          " rollup: #{alert.rollup || '-'}")

        @queues[medium.transport].push(alert)
      end

      e = notification.entry
      notification.entry = nil
      Flapjack.logger.info "pre-delete-check: notifier after alerts sent"
      Flapjack::Data::Entry.delete_if_unlinked(e)
      notification.destroy
    end

  end
end
