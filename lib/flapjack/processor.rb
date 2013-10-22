#!/usr/bin/env ruby

require 'chronic_duration'

require 'flapjack'

require 'flapjack/filters/acknowledgement'
require 'flapjack/filters/ok'
require 'flapjack/filters/scheduled_maintenance'
require 'flapjack/filters/unscheduled_maintenance'
require 'flapjack/filters/delays'

require 'flapjack/data/check'
require 'flapjack/data/notification'
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
      Flapjack.redis.expire("executive_instance:#{@instance_id}", 1036800)
      Flapjack.redis.expire("event_counters:#{@instance_id}", 1036800)
    end

    def start
      # FIXME: add an administrative function to reset all event counters
      counters = Flapjack.redis.hget('event_counters', 'all')

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

      timestamp = Time.now.to_i

      entity_name, check_name = event.id.split(':', 2);
      entity_check = Flapjack::Data::Check.intersect(:entity_name => entity_name,
        :name => check_name).all.first

      entity = nil

      if entity_check.nil?
        entity = Flapjack::Data::Entity.intersect(:name => entity_name).all.first
        # TODO raise error if entity.nil?
        entity_check = Flapjack::Data::Check.new(:entity_name => entity_name,
          :name => check_name)
        # not saving yet as check state isn't set
      end

      should_notify, previous_state = update_keys(event, entity_check, timestamp)

      entity_check.save

      if @ncsm_sched_maint
        entity_check.add_scheduled_maintenance(@ncsm_sched_maint)
        @ncsm_sched_maint = nil
      end

      unless entity.nil?
        # created a new check, so add it to the entity's check list
        entity.checks << entity_check
      end

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
        if Flapjack::Data::CheckState.ok_states.include?( event.state )
          Flapjack.redis.hincrby('event_counters', 'ok', 1)
          Flapjack.redis.hincrby("event_counters:#{@instance_id}", 'ok', 1)
        elsif Flapjack::Data::CheckState.failing_states.include?( event.state )
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

            @ncsm_sched_maint = Flapjack::Data::ScheduledMaintenance.new(:start_time => timestamp,
              :end_time => timestamp + @ncsm_duration,
              :summary => 'Automatically created for new check')
          end

          # If the service event's state is ok and there was no previous state, don't alert.
          # This stops new checks from alerting as "recovery" after they have been added.
          if Flapjack::Data::CheckState.ok_states.include?( event.state )
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

      # TODO should probably look these up by 'timestamp', last may not be safe...
      case event.type
      when 'service'
        current_state.notified = true
        current_state.notification_times += [timestamp.to_i.to_s]
        current_state.save
      when 'action'
        if event.state == 'acknowledgement'
          unsched_maint = entity_check.unscheduled_maintenances_by_start.last
          unsched_maint.notified = true
          unsched_maint.notification_times += [timestamp.to_i.to_s]
          unsched_maint.save
        end
      end

      severity = Flapjack::Data::Notification.severity_for_state(event.state,
                   max_notified_severity)

      @logger.debug("Notification is being generated for #{event.id}: " + event.inspect)

      notification = Flapjack::Data::Notification.new(
        :entity_check_id   => entity_check.id,
        :state_id          => current_state.id,
        :state_duration    => (timestamp - current_state.timestamp.to_i),
        :previous_state_id => (previous_state ? previous_state.id : nil),
        :severity          => severity,
        :type              => event.notification_type,
        :time              => event.time,
        :duration          => event.duration,
        :tags              => entity_check.tags,
      )

      Flapjack::Data::Notification.push(@notifier_queue, notification)
    end

  end
end

