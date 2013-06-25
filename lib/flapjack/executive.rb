#!/usr/bin/env ruby

require 'log4r'
require 'log4r/outputter/fileoutputter'
require 'tzinfo'
require 'active_support/time'

require 'flapjack/filters/acknowledgement'
require 'flapjack/filters/ok'
require 'flapjack/filters/scheduled_maintenance'
require 'flapjack/filters/unscheduled_maintenance'
require 'flapjack/filters/detect_mass_client_failures'
require 'flapjack/filters/delays'
require 'flapjack/data/contact'
require 'flapjack/data/entity_check'
require 'flapjack/data/notification'
require 'flapjack/data/event'
require 'flapjack/redis_pool'
require 'flapjack/utility'

require 'flapjack/gateways/email'
require 'flapjack/gateways/sms_messagenet'

module Flapjack

  class Executive

    include Flapjack::Utility

    def initialize(opts = {})
      @config = opts[:config]
      @redis_config = opts[:redis_config]
      @logger = opts[:logger]
      @redis = Flapjack::RedisPool.new(:config => @redis_config, :size => 2) # first will block

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
      @notifylog = Log4r::Logger.new("executive")
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

      @archive_events        = @config['archive_events'] || false
      @events_archive_maxage = @config['events_archive_maxage']

      # FIXME: Put loading filters into separate method
      # FIXME: should we make the filters more configurable by the end user?
      options = { :log => opts[:logger], :persistence => @redis }
      @filters = []
      @filters << Flapjack::Filters::Ok.new(options)
      @filters << Flapjack::Filters::ScheduledMaintenance.new(options)
      @filters << Flapjack::Filters::UnscheduledMaintenance.new(options)
      @filters << Flapjack::Filters::DetectMassClientFailures.new(options)
      @filters << Flapjack::Filters::Delays.new(options)
      @filters << Flapjack::Filters::Acknowledgement.new(options)

      @boot_time    = opts[:boot_time]
      @fqdn         = `/bin/hostname -f`.chomp
      @pid          = Process.pid
      @instance_id  = "#{@fqdn}:#{@pid}"

      # FIXME: all of the below keys assume there is only ever one executive running;
      # we could generate a fuid and save it to disk, and prepend it from that
      # point on...

      # FIXME: add an administrative function to reset all event counters
      if @redis.hget('event_counters', 'all').nil?
        @redis.hset('event_counters', 'all', 0)
        @redis.hset('event_counters', 'ok', 0)
        @redis.hset('event_counters', 'failure', 0)
        @redis.hset('event_counters', 'action', 0)
      end

      #@redis.zadd('executive_instances', @boot_time.to_i, @instance_id)
      @redis.hset("executive_instance:#{@instance_id}", 'boot_time', @boot_time.to_i)
      @redis.hset("event_counters:#{@instance_id}", 'all', 0)
      @redis.hset("event_counters:#{@instance_id}", 'ok', 0)
      @redis.hset("event_counters:#{@instance_id}", 'failure', 0)
      @redis.hset("event_counters:#{@instance_id}", 'action', 0)
      touch_keys
    end

    # expire instance keys after one week
    # TODO: set up a separate EM timer to reset key expiry every minute
    # and reduce the expiry to, say, five minutes
    # TODO: remove these keys on process exit
    def touch_keys
      [ "executive_instance:#{@instance_id}",
        "event_counters:#{@instance_id}",
        "event_counters:#{@instance_id}",
        "event_counters:#{@instance_id}",
        "event_counters:#{@instance_id}" ].each {|key|
          @redis.expire(key, 1036800)
        }
    end

    def start
      @logger.info("Booting main loop.")

      until @should_quit
        @logger.debug("Waiting for event...")
        event = Flapjack::Data::Event.next(:redis => @redis,
                                           :archive_events => @archive_events,
                                           :events_archive_maxage => @events_archive_maxage,
                                           :logger => @logger)
        process_event(event) unless event.nil?
      end

      @logger.info("Exiting main loop.")
    end

    # this must use a separate connection to the main Executive one, as it's running
    # from a different fiber while the main one is blocking.
    def stop
      @should_quit = true
      @redis.rpush('events', JSON.generate('type'    => 'shutdown',
                                           'host'    => '',
                                           'service' => '',
                                           'state'   => ''))
    end

  private

    def process_event(event)
      pending = Flapjack::Data::Event.pending_count(:redis => @redis)
      @logger.debug("#{pending} events waiting on the queue")
      @logger.debug("Raw event received: #{event.inspect}")
      return if ('shutdown' == event.type)

      event_str = "#{event.id}, #{event.type}, #{event.state}, #{event.summary}"
      event_str << ", #{Time.at(event.time).to_s}" if event.time
      @logger.debug("Processing Event: #{event_str}")

      entity_check = Flapjack::Data::EntityCheck.for_event_id(event.id, :redis => @redis)

      should_notify = update_keys(event, entity_check)

      if !should_notify
        @logger.debug("Not generating notifications for event #{event.id} because filtering was skipped")
        return
      elsif blocker = @filters.find {|filter| filter.block?(event) }
        @logger.debug("Not generating notifications for event #{event.id} because this filter blocked: #{blocker.name}")
        return
      end

      @logger.info("Generating notifications for event #{event_str}")
      generate_notification_messages(event, entity_check)
    end

    def update_keys(event, entity_check)

      # TODO: run touch_keys from a separate EM timer for efficiency
      touch_keys

      result = true
      timestamp = Time.now.to_i
      @event_count = @redis.hincrby('event_counters', 'all', 1)
      @redis.hincrby("event_counters:#{@instance_id}", 'all', 1)

      # FIXME skip if entity_check.nil?

      # FIXME: validate that the event is sane before we ever get here
      # FIXME: create an event if there is dodgy data

      case event.type
      # Service events represent changes in state on monitored systems
      when 'service'
        # Track when we last saw an event for a particular entity:check pair
        entity_check.last_update = timestamp

        if event.ok?
          @redis.hincrby('event_counters', 'ok', 1)
          @redis.hincrby("event_counters:#{@instance_id}", 'ok', 1)
        elsif event.failure?
          @redis.hincrby('event_counters', 'failure', 1)
          @redis.hincrby("event_counters:#{@instance_id}", 'failure', 1)
          @redis.hset('unacknowledged_failures', @event_count, event.id)
        end

        event.previous_state = entity_check.state
        event.previous_state_duration = Time.now.to_i - entity_check.last_change.to_i
        @logger.info("No previous state for event #{event.id}") if event.previous_state.nil?

        entity_check.update_state(event.state, :timestamp => timestamp,
          :summary => event.summary, :client => event.client,
          :count => @event_count, :details => event.details)

        # No state change, and event is ok, so no need to run through filters
        # OR
        # If the service event's state is ok and there was no previous state, don't alert.
        # This stops new checks from alerting as "recovery" after they have been added.
        if !event.previous_state && event.ok?
          @logger.debug("setting skip_filters to true because there was no previous state and event is ok")
          result = false
        end

        entity_check.update_current_scheduled_maintenance

      # Action events represent human or automated interaction with Flapjack
      when 'action'
        # When an action event is processed, store the event.
        @redis.hset(event.id + ':actions', timestamp, event.state)
        @redis.hincrby('event_counters', 'action', 1)
        @redis.hincrby("event_counters:#{@instance_id}", 'action', 1)

        if event.acknowledgement? && event.acknowledgement_id
          @redis.hdel('unacknowledged_failures', event.acknowledgement_id)
        end
      end

      result
    end

    # takes an event for which a notification needs to be generated, works out the type of
    # notification, updates the notification history in redis, generates the notifications
    def generate_notification_messages(event, entity_check)
      timestamp = Time.now.to_i
      notification_type = 'unknown'
      case event.type
      when 'service'
        case event.state
        when 'ok'
          notification_type = 'recovery'
        when 'warning', 'critical', 'unknown'
          notification_type = 'problem'
        end
      when 'action'
        case event.state
        when 'acknowledgement'
          notification_type = 'acknowledgement'
        when 'test_notifications'
          notification_type = 'test'
        end
      end

      max_notified_severity = entity_check.max_notified_severity_of_current_failure

      @redis.set("#{event.id}:last_#{notification_type}_notification", timestamp)
      @redis.set("#{event.id}:last_#{event.state}_notification", timestamp) if event.failure?
      @redis.rpush("#{event.id}:#{notification_type}_notifications", timestamp)
      @redis.rpush("#{event.id}:#{event.state}_notifications", timestamp) if event.failure?
      @logger.debug("Notification of type #{notification_type} is being generated for #{event.id}.")

      contacts = entity_check.contacts

      if contacts.empty?
        @logger.debug("No contacts for #{event.id}")
        @notifylog.info("#{Time.now.to_s} | #{event.id} | #{notification_type} | NO CONTACTS")
        return
      end

      notification = Flapjack::Data::Notification.for_event(
        event, :type => notification_type,
               :max_notified_severity => max_notified_severity,
               :contacts => contacts,
               :default_timezone => @default_contact_timezone,
               :logger => @logger)

      notification.messages.each do |message|
        media_type = message.medium
        contents   = message.contents
        address    = message.address
        event_id   = event.id

        @notifylog.info("#{Time.now.to_s} | #{event_id} | " +
          "#{notification_type} | #{message.contact.id} | #{media_type} | #{address}")

        unless @queues[media_type.to_sym]
          @logger.error("no queue for media type: #{media_type}")
          return
        end

        @logger.info("Enqueueing #{media_type} alert for #{event_id} to #{address}")

        if event.ok?
          message.contact.update_sent_alert_keys(
            :media => media_type,
            :check => event_id,
            :state => 'warning',
            :delete => true)
          message.contact.update_sent_alert_keys(
            :media => media_type,
            :check => event_id,
            :state => 'critical',
            :delete => true)
          message.contact.update_sent_alert_keys(
            :media => media_type,
            :check => event_id,
            :state => 'unknown',
            :delete => true)
        else
          message.contact.update_sent_alert_keys(
            :media => media_type,
            :check => event_id,
            :state => event.state)
        end

        # TODO consider changing Resque jobs to use raw blpop like the others
        case media_type.to_sym
        when :sms
          Resque.enqueue_to(@queues[:sms], Flapjack::Gateways::SmsMessagenet, contents)
        when :email
          Resque.enqueue_to(@queues[:email], Flapjack::Gateways::Email, contents)
        when :jabber
          # TODO move next line up into other notif value setting above?
          contents['event_count'] = @event_count if @event_count
          @redis.rpush(@queues[:jabber], Yajl::Encoder.encode(contents))
        when :pagerduty
          @redis.rpush(@queues[:pagerduty], Yajl::Encoder.encode(contents))
        end
      end
    end

  end
end
