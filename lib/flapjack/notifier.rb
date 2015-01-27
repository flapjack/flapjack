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
        Zermelo.redis = Flapjack.redis

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
      Flapjack.logger.debug { "Processing notification: #{notification.inspect}" }

      check       = notification.entry.state.check
      check_name  = check.name

      alerts = notification.alerts_for(check,
        :transports => @queues.keys,
        :default_timezone => @default_contact_timezone)

      if alerts.nil? || alerts.empty?
        Flapjack.logger.info { "No alerts" }
      else
        Flapjack.logger.info { "Alerts: #{alerts.size}" }

        alerts.each do |alert|
          medium = alert.medium

          Flapjack.logger.info {
            "#{check_name} | #{medium.contact.id} | " \
            "#{medium.transport} | #{medium.address}\n" \
            "Enqueueing #{medium.transport} alert for " \
            "#{check_name} to #{medium.address} " \
            " rollup: #{alert.rollup || '-'}"
          }

          @queues[medium.transport].push(alert)
        end
      end

      e = notification.entry
      notification.entry = nil
      Flapjack::Data::Entry.delete_if_unlinked(e)
      notification.destroy
    end

  end
end
