#!/usr/bin/env ruby

require 'chronic_duration'

require 'flapjack'

require 'flapjack/filters/acknowledgement'
require 'flapjack/filters/ok'
require 'flapjack/filters/scheduled_maintenance'
require 'flapjack/filters/unscheduled_maintenance'
require 'flapjack/filters/detect_mass_client_failures'
require 'flapjack/filters/delays'

require 'flapjack/data/entity_check'
require 'flapjack/data/event'
require 'flapjack/exceptions'
require 'flapjack/utility'

module Flapjack

  class Processor

    include Flapjack::Utility

    def initialize(opts = {})
      @lock = opts[:lock]

      @config = opts[:config]
      @logger = opts[:logger]

      @boot_time    = opts[:boot_time]

      @queue = @config['queue'] || 'events'

      @notifier_queue = @config['notifier_queue'] || 'notifications'

      @archive_events        = @config['archive_events'] || false
      @events_archive_maxage = @config['events_archive_maxage']

      ncsm_duration_conf = @config['new_check_scheduled_maintenance_duration'] || '100 years'
      @ncsm_duration = ChronicDuration.parse(ncsm_duration_conf)

      @exit_on_queue_empty = !! @config['exit_on_queue_empty']

      options = { :logger => opts[:logger] }
      @filters = []
      @filters << Flapjack::Filters::Ok.new(options)
      @filters << Flapjack::Filters::ScheduledMaintenance.new(options)
      @filters << Flapjack::Filters::UnscheduledMaintenance.new(options)
      @filters << Flapjack::Filters::DetectMassClientFailures.new(options)
      @filters << Flapjack::Filters::Delays.new(options)
      @filters << Flapjack::Filters::Acknowledgement.new(options)

      fqdn          = `/bin/hostname -f`.chomp
      pid           = Process.pid
      @instance_id  = "#{fqdn}:#{pid}"

      # FIXME: all of the below keys assume there is only ever one executive running;
      # we could generate a fuid and save it to disk, and prepend it from that
      # point on...
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
          Flapjack.redis.expire(key, 1036800)
        }
    end

    def start
      # FIXME: add an administrative function to reset all event counters
      if Flapjack.redis.hget('event_counters', 'all').nil?
        Flapjack.redis.hset('event_counters', 'all', 0)
        Flapjack.redis.hset('event_counters', 'ok', 0)
        Flapjack.redis.hset('event_counters', 'failure', 0)
        Flapjack.redis.hset('event_counters', 'action', 0)
      end

      #Flapjack.redis.zadd('executive_instances', @boot_time.to_i, @instance_id)
      Flapjack.redis.hset("executive_instance:#{@instance_id}", 'boot_time', @boot_time.to_i)
      Flapjack.redis.hset("event_counters:#{@instance_id}", 'all', 0)
      Flapjack.redis.hset("event_counters:#{@instance_id}", 'ok', 0)
      Flapjack.redis.hset("event_counters:#{@instance_id}", 'failure', 0)
      Flapjack.redis.hset("event_counters:#{@instance_id}", 'action', 0)
      touch_keys

      @logger.info("Booting main loop.")

      loop do
        @lock.synchronize do
          Flapjack::Data::Event.foreach_on_queue(@queue,
                                                 :archive_events => @archive_events,
                                                 :events_archive_maxage => @events_archive_maxage,
                                                 :logger => @logger) do |event|
            process_event(event)
          end
        end

        raise Flapjack::GlobalStop if @config['exit_on_queue_empty']

        Flapjack::Data::Event.wait_for_queue(@queue)
      end
    end

    def stop_type
      :exception
    end

  private

    def process_event(event)
      pending = Flapjack::Data::Event.pending_count(@queue)
      @logger.debug("#{pending} events waiting on the queue")
      @logger.debug("Raw event received: #{event.inspect}")

      event_str = "#{event.id}, #{event.type}, #{event.state}, #{event.summary}"
      event_str << ", #{Time.at(event.time).to_s}" if event.time
      @logger.debug("Processing Event: #{event_str}")

      entity_check = Flapjack::Data::EntityCheck.for_event_id(event.id)
      timestamp = Time.now.to_i

      event.tags = (event.tags || Flapjack::Data::TagSet.new) + entity_check.tags

      should_notify = update_keys(event, entity_check, timestamp)

      if !should_notify
        @logger.debug("Not generating notification for event #{event.id} because filtering was skipped")
        return
      elsif blocker = @filters.find {|filter| filter.block?(event) }
        @logger.debug("Not generating notification for event #{event.id} because this filter blocked: #{blocker.name}")
        return
      end

      @logger.info("Generating notification for event #{event_str}")
      generate_notification(event, entity_check, timestamp)
    end

    def update_keys(event, entity_check, timestamp)
      # TODO: run touch_keys from a separate EM timer for efficiency
      touch_keys

      result = true

      event.counter = Flapjack.redis.hincrby('event_counters', 'all', 1)
      Flapjack.redis.hincrby("event_counters:#{@instance_id}", 'all', 1)

      # FIXME skip if entity_check.nil?

      # FIXME: validate that the event is sane before we ever get here
      # FIXME: create an event if there is dodgy data

      case event.type
      # Service events represent changes in state on monitored systems
      when 'service'
        # Track when we last saw an event for a particular entity:check pair
        entity_check.last_update = timestamp

        if event.ok?
          Flapjack.redis.hincrby('event_counters', 'ok', 1)
          Flapjack.redis.hincrby("event_counters:#{@instance_id}", 'ok', 1)
        elsif event.failure?
          Flapjack.redis.hincrby('event_counters', 'failure', 1)
          Flapjack.redis.hincrby("event_counters:#{@instance_id}", 'failure', 1)
          Flapjack.redis.hset('unacknowledged_failures', event.counter, event.id)
        end

        event.previous_state = entity_check.state

        if event.previous_state.nil?
          @logger.info("No previous state for event #{event.id}")

          if @ncsm_duration >= 0
            @logger.info("Setting scheduled maintenance for #{time_period_in_words(@ncsm_duration)}")
            entity_check.create_scheduled_maintenance(timestamp,
              @ncsm_duration, :summary => 'Automatically created for new check')
          end
        else
          event.previous_state_duration = timestamp - entity_check.last_change.to_i
        end

        entity_check.update_state(event.state, :timestamp => timestamp,
          :summary => event.summary, :client => event.client,
          :count => event.counter, :details => event.details)

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
        Flapjack.redis.hset(event.id + ':actions', timestamp, event.state)
        Flapjack.redis.hincrby('event_counters', 'action', 1)
        Flapjack.redis.hincrby("event_counters:#{@instance_id}", 'action', 1)

        if event.acknowledgement? && event.acknowledgement_id
          Flapjack.redis.hdel('unacknowledged_failures', event.acknowledgement_id)
        end
      end

      result
    end

    def generate_notification(event, entity_check, timestamp)
      notification_type = Flapjack::Data::Notification.type_for_event(event)
      max_notified_severity = entity_check.max_notified_severity_of_current_failure

      Flapjack.redis.set("#{event.id}:last_#{notification_type}_notification", timestamp)
      Flapjack.redis.set("#{event.id}:last_#{event.state}_notification", timestamp) if event.failure?
      Flapjack.redis.rpush("#{event.id}:#{notification_type}_notifications", timestamp)
      Flapjack.redis.rpush("#{event.id}:#{event.state}_notifications", timestamp) if event.failure?
      @logger.debug("Notification of type #{notification_type} is being generated for #{event.id}: " + event.inspect)

      severity = Flapjack::Data::Notification.severity_for_event(event, max_notified_severity)
      last_state = entity_check.historical_state_before(timestamp)

      Flapjack::Data::Notification.push(@notifier_queue, event,
        :type => notification_type, :severity => severity, :last_state => last_state
      )
    end

  end
end
