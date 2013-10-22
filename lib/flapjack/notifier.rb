#!/usr/bin/env ruby

require 'active_support/time'

require 'oj'

require 'flapjack'

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
      loop do
        @lock.synchronize do
          Flapjack::Data::Notification.foreach_on_queue(@notifications_queue) {|notif|
            process_notification(notif)
          }
        end

        Flapjack::Data::Notification.wait_for_queue(@notifications_queue)
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

      timestamp = Time.now
      entity_check_id = notification.entity_check_id
      entity_check = Flapjack::Data::Check.find_by_id(entity_check_id)

      contacts = entity_check.contacts.all + entity_check.entity.contacts.all

      if contacts.empty?
        @logger.debug("No contacts for '#{entity_check.entity_name}:#{entity_check.name}'")
        @notifylog.info("#{entity_check.entity_name}:#{entity_check.name} | #{notification.type} | NO CONTACTS")
        return
      end

      messages = notification.messages(contacts,
        :default_timezone => @default_contact_timezone,
        :logger => @logger)

      notification_contents = notification.contents

      messages.each do |message|
        media_type = message.medium
        address    = message.address
        contents   = message.contents.merge(notification_contents)

        @notifylog.info("#{entity_check.entity_name}:#{entity_check.name} | " +
          "#{notification.type} | #{message.contact.id} | #{media_type} | #{address}")

        unless @queues[media_type.to_sym]
          @logger.error("no queue for media type: #{media_type}")
          return
        end

        @logger.info("Enqueueing #{media_type} alert for #{entity_check.entity_name}:#{entity_check.name} to #{address}")

        contact = message.contact

        if ['recovery', 'acknowledgement'].include?(notification.type)

          ['warning', 'critical', 'unknown'].each do |alert_state|
            contact.update_sent_alert_keys(
              :media => media_type,
              :entity_check => entity_check,
              :state => alert_state,
              :delete => true)
          end
        else
          contact.update_sent_alert_keys(
            :media => media_type,
            :entity_check => entity_check,
            :state => notification.state.state)
        end

        contents_tags = contents['tags']
        contents['tags'] = contents_tags.is_a?(Set) ? contents_tags.to_a : contents_tags

        if [:sms, :email, :jabber, :pagerduty].include?(media_type.to_sym)
          Flapjack::Data::Message.push(@queues[media_type.to_sym], contents)
        else
          # TODO log warning
        end
      end
    end

  end
end
