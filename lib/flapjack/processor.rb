#!/usr/bin/env ruby

require 'chronic_duration'

require 'flapjack/redis_proxy'

require 'flapjack/filters/acknowledgement'
require 'flapjack/filters/ok'
require 'flapjack/filters/scheduled_maintenance'
require 'flapjack/filters/unscheduled_maintenance'
require 'flapjack/filters/delays'

require 'flapjack/data/check'
require 'flapjack/data/event'
require 'flapjack/data/notification'
require 'flapjack/data/statistic'

require 'flapjack/exceptions'
require 'flapjack/utility'

module Flapjack

  class Processor

    include Flapjack::Utility

    def initialize(opts = {})
      @lock = opts[:lock]

      @config = opts[:config]

      @boot_time = opts[:boot_time]

      @queue = @config['queue'] || 'events'

      @initial_failure_delay = @config['initial_failure_delay']
      if !@initial_failure_delay.is_a?(Integer) || (@initial_failure_delay < 0)
        @initial_failure_delay = nil
      end

      @repeat_failure_delay = @config['repeat_failure_delay']
      if !@repeat_failure_delay.is_a?(Integer) || (@repeat_failure_delay < 0)
        @repeat_failure_delay = nil
      end

      @initial_recovery_delay = @config['initial_recovery_delay']
      if !@initial_recovery_delay.is_a?(Integer) || (@initial_recovery_delay < 0)
        @initial_recovery_delay = nil
      end

      @notifier_queue = Flapjack::RecordQueue.new(@config['notifier_queue'] || 'notifications',
                 Flapjack::Data::Notification)

      @archive_events        = @config['archive_events'] || false
      @events_archive_maxage = @config['events_archive_maxage']

      ncsm_duration_conf = @config['new_check_scheduled_maintenance_duration'] || '100 years'
      @ncsm_duration = ChronicDuration.parse(ncsm_duration_conf, :keep_zero => true)

      ncsm_ignore = @config['new_check_scheduled_maintenance_ignore_regex']
      @ncsm_ignore_regex = if ncsm_ignore.nil? || ncsm_ignore.strip.empty?
        nil
      else
        Regexp.new(ncsm_ignore)
      end

      @exit_on_queue_empty = !!@config['exit_on_queue_empty']

      @filters = [Flapjack::Filters::Ok.new,
                  Flapjack::Filters::ScheduledMaintenance.new,
                  Flapjack::Filters::UnscheduledMaintenance.new,
                  Flapjack::Filters::Delays.new,
                  Flapjack::Filters::Acknowledgement.new]

      fqdn          = `/bin/hostname -f`.chomp
      pid           = Process.pid
      @instance_id  = "#{fqdn}:#{pid}"
    end

    def start_stats
      empty_stats = {:created_at => @boot_time, :all_events => 0,
        :ok_events => 0, :failure_events => 0, :action_events => 0,
        :invalid_events => 0}

      @global_stats = Flapjack::Data::Statistic.
        intersect(:instance_name => 'global').all.first

      if @global_stats.nil?
        @global_stats = Flapjack::Data::Statistic.new(empty_stats.merge(
          :instance_name => 'global'))
        @global_stats.save!
      end

      @instance_stats = Flapjack::Data::Statistic.new(empty_stats.merge(
        :instance_name => @instance_id))
      @instance_stats.save!
    end

    def start
      Flapjack.logger.info("Booting main loop.")

      begin
        Zermelo.redis = Flapjack.redis

        start_stats

        queue = (@config['queue'] || 'events')

        loop do
          @lock.synchronize do
            foreach_on_queue(queue) {|event| process_event(event)}
          end

          raise Flapjack::GlobalStop if @exit_on_queue_empty

          wait_for_queue(queue)
        end

      ensure
        @instance_stats.destroy unless @instance_stats.nil? || !@instance_stats.persisted?
        Flapjack.redis.quit
      end
    end

    def stop_type
      :exception
    end

  private

    def foreach_on_queue(queue, opts = {})
      base_time_str = Time.now.utc.strftime "%Y%m%d%H"
      rejects = "events_rejected:#{base_time_str}"
      archive = @archive_events ? "events_archive:#{base_time_str}" : nil
      max_age = archive ? @events_archive_maxage : nil

      while event_json = (archive ? Flapjack.redis.rpoplpush(queue, archive) :
                                    Flapjack.redis.rpop(queue))
        parsed, errors = Flapjack::Data::Event.parse_and_validate(event_json)
        if !errors.nil? && !errors.empty?
          Flapjack.redis.multi do |multi|
            if archive
              multi.lrem(archive, 1, event_json)
            end
            multi.lpush(rejects, event_json)
            @global_stats.all_events       += 1
            @global_stats.invalid_events   += 1
            @instance_stats.all_events     += 1
            @instance_stats.invalid_events += 1
            if archive
              multi.expire(archive, max_age)
            end
          end
          Flapjack::Data::Statistic.lock do
            @global_stats.save!
            @instance_stats.save!
          end
          Flapjack.logger.error {
            error_str = errors.nil? ? '' : errors.join(', ')
            "Invalid event data received, #{error_str} #{parsed.inspect}"
          }
        else
          Flapjack.redis.expire(archive, max_age) if archive
          yield Flapjack::Data::Event.new(parsed) if block_given?
        end
      end
    end

    def wait_for_queue(queue)
      Flapjack.redis.brpop("#{queue}_actions")
    end

    def process_event(event)
      Flapjack.logger.debug {
        pending = Flapjack::Data::Event.pending_count(@queue)
        "#{pending} events waiting on the queue"
      }
      Flapjack.logger.debug { "Event received: #{event.inspect}" }
      Flapjack.logger.debug { "Processing Event: #{event.dump}" }

      timestamp = Time.now

      event_condition = case event.state
      when 'acknowledgement', /\Atest_notifications(?:\s+#{Flapjack::Data::Condition.unhealthy.keys.join('|')})?\z/
        nil
      else
        cond = Flapjack::Data::Condition.for_name(event.state)
        if cond.nil?
          Flapjack.logger.error { "Invalid event received: #{event.inspect}" }
          Flapjack::Data::Statistic.lock do
            @global_stats.all_events       += 1
            @global_stats.invalid_events   += 1
            @instance_stats.all_events     += 1
            @instance_stats.invalid_events += 1
            @global_stats.save!
            @instance_stats.save!
          end
          return
        end
        cond
      end

      Flapjack::Data::Check.lock(Flapjack::Data::State,
        Flapjack::Data::ScheduledMaintenance, Flapjack::Data::UnscheduledMaintenance,
        Flapjack::Data::Tag,
        # Flapjack::Data::Route,
        Flapjack::Data::Medium,
        Flapjack::Data::Notification, Flapjack::Data::Statistic) do

        check = Flapjack::Data::Check.intersect(:name => event.id).all.first ||
          Flapjack::Data::Check.new(:name => event.id)

        # result will be nil if check has been created via API but has no events
        old_state = check.id.nil? ? nil : check.states.first

        # NB new_state won't be saved unless;
        # * the condition differs from old_state (goes into history); or
        # * it's being used for a notification (attach to medium, notification)
        new_state = Flapjack::Data::State.new(:created_at => timestamp,
          :updated_at => timestamp)

        update_check(check, old_state, new_state, event, event_condition,
                     timestamp)

        check.enabled = true unless event_condition.nil?

        ncsm_sched_maint = nil
        if check.id.nil? && (@ncsm_duration > 0) && (@ncsm_ignore_regex.nil? ||
          @ncsm_ignore_regex.match(check.name).nil?)

          Flapjack.logger.info { "Setting scheduled maintenance for #{time_period_in_words(@ncsm_duration)}" }
          ncsm_sched_maint = Flapjack::Data::ScheduledMaintenance.new(:start_time => timestamp,
            :end_time => timestamp + @ncsm_duration,
            :summary => 'Automatically created for new check')
          ncsm_sched_maint.save!
        end

        check.save! # no-op if not new and not changed
        check.scheduled_maintenances << ncsm_sched_maint unless ncsm_sched_maint.nil?

        @global_stats.save!
        @instance_stats.save!

        if (old_state.nil? || old_state.condition.nil?) && !event_condition.nil? &&
          Flapjack::Data::Condition.healthy?(event_condition.name)

          new_state.save!
          check.states << new_state
          check.current_state = new_state
          old_state.destroy unless old_state.nil? # will fail if still linked

          # If the service event's condition is ok and there was no previous condition, don't alert.
          # This stops new checks from alerting as "recovery" after they have been added.
          Flapjack.logger.debug {
            "Not generating notification for event #{event.id} because " \
            "filtering was skipped"
          }

        else
          # only change notification delays on service (non-action) events;
          # fall back to check-local, config-global or default values unless
          # sustained by the event flow
          init_fail_delay = (event_condition.nil? ? nil : event.initial_failure_delay) ||
                            check.initial_failure_delay ||
                            @initial_failure_delay ||
                            Flapjack::DEFAULT_INITIAL_FAILURE_DELAY

          repeat_fail_delay = (event_condition.nil? ? nil : event.repeat_failure_delay) ||
                              check.repeat_failure_delay ||
                              @repeat_failure_delay ||
                              Flapjack::DEFAULT_REPEAT_FAILURE_DELAY

          init_recov_delay = (event_condition.nil? ? nil : event.initial_recovery_delay) ||
                             check.initial_recovery_delay ||
                             @initial_recovery_delay ||
                             Flapjack::DEFAULT_INITIAL_RECOVERY_DELAY

          filter_opts = {
            :initial_failure_delay => init_fail_delay,
            :repeat_failure_delay => repeat_fail_delay,
            :initial_recovery_delay => init_recov_delay,
            :old_state => old_state, :new_state => new_state,
            :timestamp => timestamp, :duration => event.duration
          }

          # acks only go into latest_notifications
          save_to_history = new_state.action.nil? && !event_condition.nil? &&
            (old_state.nil? || (old_state.condition != event_condition.name))

          if save_to_history
            new_state.save!
            check.states << new_state
            check.current_state = new_state
          elsif new_state.action.nil?
            old_state.updated_at = timestamp
            old_state.summary = new_state.summary
            old_state.details = new_state.details
            old_state.save!
          end

          blocker = @filters.find {|f| f.block?(check, filter_opts) }

          if blocker.nil?
            Flapjack.logger.info { "Generating notification for event #{event.dump}" }
            new_state.save! unless new_state.persisted?
            generate_notification(check, old_state, new_state, event,
              event_condition)
          else
            Flapjack.logger.debug {
              "Not generating notification for event #{event.id} " \
              "because this filter blocked: #{blocker.name}"
            }
          end

        end
      end
    end

    def update_check(check, old_state, new_state, event, event_condition, timestamp)
      @global_stats.all_events   += 1
      @instance_stats.all_events += 1

      event.counter = @global_stats.all_events

      # ncsm_sched_maint  = nil

      if event_condition.nil?
        # Action events represent human or automated interaction with Flapjack
        new_state.action = event.state
        new_state.condition = old_state.condition unless old_state.nil?

        unless new_state.action =~ /\Atest_notifications(?:\s+#{Flapjack::Data::Condition.unhealthy.keys.join('|')})?\z/
          @global_stats.action_events   += 1
          @instance_stats.action_events += 1
        end
      else
        # Service events represent current state of checks on monitored systems
        check.failing = !Flapjack::Data::Condition.healthy?(event_condition.name)
        check.condition = event_condition.name

        if check.failing
          @global_stats.failure_events   += 1
          @instance_stats.failure_events += 1
        else
          @global_stats.ok_events   += 1
          @instance_stats.ok_events += 1
        end

        new_state.condition = event_condition.name
        new_state.perfdata = event.perfdata
      end

      new_state.summary   = event.summary
      new_state.details   = event.details
    end

    def generate_notification(check, old_state, new_state, event, event_condition)
      severity = nil

      # accepts test_notifications without condition, for backwards compatibility
      if new_state.action =~ /\Atest_notifications(\s+#{Flapjack::Data::Condition.unhealthy.keys.join('|')})?\z/
        # the state won't be preserved for any time after the notification is
        # sent via association to a state or check
        severity = Regexp.last_match(1) || Flapjack::Data::Condition.most_unhealthy
      else
        latest_notif = check.latest_notifications

        notification_ids_to_remove = if new_state.action.nil?
          latest_notif.intersect(:condition => new_state.condition).ids
        else
          latest_notif.intersect(:action => new_state.action).ids
        end
        latest_notif.add(new_state)
        latest_notif.remove_ids(*notification_ids_to_remove) unless notification_ids_to_remove.empty?

        most_severe = check.most_severe

        most_severe_cond = most_severe.nil? ? nil :
          Flapjack::Data::Condition.for_name(most_severe.condition)

        if !event_condition.nil? &&
          Flapjack::Data::Condition.unhealthy.has_key?(event_condition.name) &&
          (most_severe_cond.nil? || (event_condition < most_severe_cond))

          check.most_severe = new_state
          most_severe_cond = event_condition
        elsif 'acknowledgement'.eql?(new_state.action)
          check.most_severe = nil
        end

        severity = most_severe_cond.nil? ? 'ok' : most_severe_cond.name
      end

      Flapjack.logger.info { "severity #{severity}"}

      Flapjack.logger.debug("Notification is being generated for #{event.id}: " + event.inspect)

      event_hash = (event_condition.nil? || Flapjack::Data::Condition.healthy?(event_condition.name)) ?
        nil : check.ack_hash

      condition_duration = old_state.nil? ? nil :
                             (new_state.created_at - old_state.created_at)

      notification = Flapjack::Data::Notification.new(:duration => event.duration,
        :severity => severity, :condition_duration => condition_duration,
        :event_hash => event_hash)
      notification.save!

      notification.state = new_state
      check.notifications << notification

      @notifier_queue.push(notification)

      return if new_state.action =~ /\Atest_notifications(?:\s+#{Flapjack::Data::Condition.unhealthy.keys.join('|')})?\z/

      Flapjack.logger.info "notification count: #{check.notification_count}"

      if check.notification_count.nil?
        check.notification_count = 1
      else
        check.notification_count += 1
      end
      check.save!

      Flapjack.logger.info "#{check.name} #{check.errors.full_messages} notification count: #{check.notification_count}"
    end
  end
end
