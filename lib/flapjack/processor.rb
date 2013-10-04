#!/usr/bin/env ruby

require 'chronic_duration'

require 'flapjack'

require 'flapjack/filters/acknowledgement'
require 'flapjack/filters/ok'
require 'flapjack/filters/scheduled_maintenance'
require 'flapjack/filters/unscheduled_maintenance'
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

      filter_opts = {:logger => opts[:logger]}

      @filters = [Flapjack::Filters::Ok.new(filter_opts),
                  Flapjack::Filters::ScheduledMaintenance.new(filter_opts),
                  Flapjack::Filters::UnscheduledMaintenance.new(filter_opts),
                  Flapjack::Filters::Delays.new(filter_opts),
                  Flapjack::Filters::Acknowledgement.new(filter_opts)]

      fqdn          = `/bin/hostname -f`.chomp
      pid           = Process.pid
      @instance_id  = "#{fqdn}:#{pid}"
    end

    # expire instance keys after one week
    # TODO: set up a separate timer to reset key expiry every minute
    # and reduce the expiry to, say, five minutes
    # TODO: remove these keys on process exit
    def touch_keys
      [ "executive_instance:#{@instance_id}",
        "event_counters:#{@instance_id}" ].each {|key|
          Flapjack.redis.expire(key, 1036800)
        }
    end

    def start
      # FIXME: add an administrative function to reset all event counters
      counters = Flapjack.redis.hget('event_counters', 'all').nil?

      Flapjack.redis.multi

      if counters.nil?
        Flapjack.redis.hmset('event_counters',
                             'all', 0, 'ok', 0, 'failure', 0, 'action', 0)
      end

      # Flapjack.redis.zadd('executive_instances', @boot_time.to_i, @instance_id)
      Flapjack.redis.hset("executive_instance:#{@instance_id}", 'boot_time', @boot_time.to_i)
      Flapjack.redis.hmset("event_counters:#{@instance_id}",
                           'all', 0, 'ok', 0, 'failure', 0, 'action', 0)
      touch_keys

      Flapjack.redis.exec

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

      entity_name, check_name = event_id.split(':', 2);
      entity_check = Flapjack::Data::EntityCheckR.intersect(:entity_name => entity_name,
        :name => check_name).first

      if entity_check.nil?
        entity_check.entity_name = entity_name
        entity_check.name        = check_name
        # not saving yet as state isn't set
      end

      timestamp = Time.now.to_i

      should_notify, previous_state = update_keys(event, entity_check, timestamp)

      if !should_notify
        @logger.debug("Not generating notification for event #{event.id} because filtering was skipped")
        return
      elsif blocker = @filters.find {|filter| filter.block?(event, entity_check, previous_state) }
        @logger.debug("Not generating notification for event #{event.id} because this filter blocked: #{blocker.name}")
        return
      end

      # redis_record rework -- up to here
      @logger.info("Generating notification for event #{event_str}")
      generate_notification(event, entity_check, timestamp, previous_state)
    end

    def update_keys(event, entity_check, timestamp)
      touch_keys

      result = true
      previous_state = nil

      event.counter = Flapjack.redis.hincrby('event_counters', 'all', 1)
      Flapjack.redis.hincrby("event_counters:#{@instance_id}", 'all', 1)

      # FIXME skip if entity_check.nil?

      # FIXME: validate that the event is sane before we ever get here
      # FIXME: create an event if there is dodgy data

      case event.type
      # Service events represent changes in state on monitored systems
      when 'service'
        Flapjack.redis.multi
        if Flapjack::Data::CheckStateR.ok_states.include?( event.state )
          Flapjack.redis.hincrby('event_counters', 'ok', 1)
          Flapjack.redis.hincrby("event_counters:#{@instance_id}", 'ok', 1)
        elsif Flapjack::Data::CheckStateR.failing_states.include?( event.state )
          Flapjack.redis.hincrby('event_counters', 'failure', 1)
          Flapjack.redis.hincrby("event_counters:#{@instance_id}", 'failure', 1)
          # Flapjack.redis.hset('unacknowledged_failures', event.counter, event.id)
        end
        Flapjack.redis.exec

        previous_state = entity_check.states.last

        if previous_state.nil?
          @logger.info("No previous state for event #{event.id}")

          if @ncsm_duration >= 0
            @logger.info("Setting scheduled maintenance for #{time_period_in_words(@ncsm_duration)}")
            entity_check.create_scheduled_maintenance(timestamp,
              @ncsm_duration, :summary => 'Automatically created for new check')
          end

          # If the service event's state is ok and there was no previous state, don't alert.
          # This stops new checks from alerting as "recovery" after they have been added.
          if Flapjack::Data::CheckStateR.ok_states.include?( event.state )
            @logger.debug("setting skip_filters to true because there was no previous state and event is ok")
            result = false
          end
        end

        # NB this creates a new entry in entity_check.states, through the magic
        # of callbacks
        entity_check.state       = event.state
        entity_check.summary     = event.summary
        entity_check.details     = event.details
        entity_check.count       = event.counter
        entity_check.last_update = timestamp
        entity_check.save

      # Action events represent human or automated interaction with Flapjack
      when 'action'
        # When an action event is processed, store the event.
        Flapjack.redis.multi
        # Flapjack.redis.hset(event.id + ':actions', timestamp, event.state)
        Flapjack.redis.hincrby('event_counters', 'action', 1)
        Flapjack.redis.hincrby("event_counters:#{@instance_id}", 'action', 1)

        if event.acknowledgement? && event.acknowledgement_id
          # Flapjack.redis.hdel('unacknowledged_failures', event.acknowledgement_id)
        end
        Flapjack.redis.exec
      end

      [result, previous_state]
    end

    def generate_notification(event, entity_check, timestamp, previous_state)
      max_notified_severity = entity_check.max_notified_severity_of_current_failure

      current_state = entity_check.states.last
      current_state.notified = true
      current_state.save

      @logger.debug("Notification is being generated for #{event.id}: " + event.inspect)

      severity = Flapjack::Data::NotificationR.severity_for_state(event.state,
                   max_notified_severity)
      tag_data = entity_check.tags

      notification = Flapjack::Data::NotificationR.new(
        :state_id          => current_state.id,
        :state_duration    => (timestamp - current_state.timestamp),
        :previous_state_id => previous_state.id,
        :severity          => severity,
        :time              => event.time,
        :duration          => event.duration,
        :tags              => (tag_data ? tag_data.to_a : nil),
      )

    if notification.valid?
      Flapjack::Data::NotificationR.push(@notifier_queue, notification)
    end

  end
end

