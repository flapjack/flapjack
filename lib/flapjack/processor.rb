#!/usr/bin/env ruby

require 'chronic_duration'

require 'flapjack/redis_proxy'

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

      @boot_time = opts[:boot_time]

      @queue = @config['queue'] || 'events'

      @initial_failure_delay = @config['initial_failure_delay']
      if !@initial_failure_delay.is_a?(Integer) || (@initial_failure_delay < 1)
        @initial_failure_delay = nil
      end

      @repeat_failure_delay = @config['repeat_failure_delay']
      if !@repeat_failure_delay.is_a?(Integer) || (@repeat_failure_delay < 1)
        @repeat_failure_delay = nil
      end

      @notifier_queue = Flapjack::RecordQueue.new(@config['notifier_queue'] || 'notifications',
                 Flapjack::Data::Notification)

      @archive_events        = @config['archive_events'] || false
      @events_archive_maxage = @config['events_archive_maxage']

      ncsm_duration_conf = @config['new_check_scheduled_maintenance_duration'] || '100 years'
      @ncsm_duration = ChronicDuration.parse(ncsm_duration_conf, :keep_zero => true)

      @ncsm_ignore_tags = @config['new_check_scheduled_maintenance_ignore_tags'] || []

      @exit_on_queue_empty = !!@config['exit_on_queue_empty']

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
    def touch_keys(multi)
      multi.expire("executive_instance:#{@instance_id}", 1036800)
      multi.expire("event_counters:#{@instance_id}", 1036800)
    end

    def start
      @logger.info("Booting main loop.")

      begin
        Sandstorm.redis = Flapjack.redis

        # FIXME: add an administrative function to reset all event counters

        counter_types = ['all', 'ok', 'failure', 'action', 'invalid']
        counters = Hash[counter_types.zip(Flapjack.redis.hmget('event_counters', *counter_types))]

        Flapjack.redis.multi do |multi|
          counter_types.select {|ct| counters[ct].nil? }.each do |counter_type|
            multi.hset('event_counters', counter_type, 0)
          end

          multi.zadd('executive_instances', @boot_time.to_i, @instance_id)
          multi.hset("executive_instance:#{@instance_id}", 'boot_time', @boot_time.to_i)
          multi.hmset("event_counters:#{@instance_id}",
                               'all', 0, 'ok', 0, 'failure', 0, 'action', 0, 'invalid', 0)
          touch_keys(multi)
        end

        queue = (@config['queue'] || 'events')

        loop do
          @lock.synchronize do
            foreach_on_queue(queue,
                             :archive_events => @archive_events,
                             :events_archive_maxage => @events_archive_maxage) do |event|
              process_event(event)
            end
          end

          raise Flapjack::GlobalStop if @exit_on_queue_empty

          wait_for_queue(queue)
        end

      ensure
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
      archive = opts[:archive_events] ? "events_archive:#{base_time_str}" : nil
      max_age = archive ? opts[:events_archive_maxage] : nil

      while event_json = (archive ? Flapjack.redis.rpoplpush(queue, archive) :
                                    Flapjack.redis.rpop(queue))
        parsed = Flapjack::Data::Event.parse_and_validate(event_json, :logger => @logger)
        if parsed.nil?
          Flapjack.redis.multi do |multi|
            if archive
              multi.lrem(archive, 1, event_json)
            end
            multi.lpush(rejects, event_json)
            multi.hincrby('event_counters', 'all', 1)
            multi.hincrby("event_counters:#{@instance_id}", 'all', 1)
            multi.hincrby('event_counters', 'invalid', 1)
            multi.hincrby("event_counters:#{@instance_id}", 'invalid', 1)
            if archive
              multi.expire(archive, max_age)
            end
          end
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
      @logger.debug {
        pending = Flapjack::Data::Event.pending_count(@queue)
        "#{pending} events waiting on the queue"
      }
      @logger.debug { "Event received: #{event.inspect}" }
      @logger.debug { "Processing Event: #{event.dump}" }

      timestamp = Time.now

      event_condition = case event.state
      when 'acknowledgement', 'test_notifications'
        nil
      else
        cond = Flapjack::Data::Condition.for_name(event.state)
        if cond.nil?
          @logger.error { "Invalid event received: #{event.inspect}" }
          Flapjack.redis.multi do |multi|
            multi.hincrby('event_counters', 'invalid', 1)
            multi.hincrby("event_counters:#{@instance_id}", 'invalid', 1)
          end
          return
        end
        cond
      end

      old_state = nil
      new_state = nil

      # TODO remove Medium from lock if alerting_media association is deleted
      Flapjack::Data::Check.lock(Flapjack::Data::State,
        Flapjack::Data::ScheduledMaintenance, Flapjack::Data::Tag,
        Flapjack::Data::Medium, Flapjack::Data::UnscheduledMaintenance,
        Flapjack::Data::Notification) do

        # TODO rethink name / event_id mapping, current behaviour is quick
        # hack for Flapjack v1 equivalence
        check = Flapjack::Data::Check.intersect(:name => event.id).all.first ||
          Flapjack::Data::Check.new(:name => event.id)

        # result will be nil if check has been created via API but has no events
        old_state = check.id.nil? ? nil : check.states.intersect(:condition_changed => true).last
        new_state = update_check(check, old_state, event,
                                 event_condition, timestamp)

        check.enabled = true unless event_condition.nil?
        check.save # no-op if not new and not changed

        if !event_condition.nil? && Flapjack::Data::Condition.healthy?(event_condition.name) && old_state.nil?
          new_state.save
          check.states << new_state

          # If the service event's state is ok and there was no previous state, don't alert.
          # This stops new checks from alerting as "recovery" after they have been added.
          @logger.debug {
            "Not generating notification for event #{event.id} because " \
            "filtering was skipped"
          }

        else
          filter_opts = {
            :initial_failure_delay => @initial_failure_delay,
            :repeat_failure_delay => @repeat_failure_delay,
            :old_state => old_state, :new_state => new_state,
            :timestamp => timestamp, :duration => event.duration
          }

          blocker = @filters.find {|f| f.block?(check, filter_opts) }

          if blocker.nil?
            @logger.info { "Generating notification for event #{event.dump}" }
            generate_notification(check, old_state, new_state, event, event_condition)
          else
            new_state.save
            check.states << new_state

            @logger.debug { "Not generating notification for event #{event.id} " \
                            "because this filter blocked: #{blocker.name}" }
          end
        end
      end
    end

    def update_check(check, old_state, event, event_condition, timestamp)
      Flapjack.redis.multi do |multi|
        touch_keys(multi)
      end

      event.counter = Flapjack.redis.hincrby('event_counters', 'all', 1)
      Flapjack.redis.hincrby("event_counters:#{@instance_id}", 'all', 1)

      new_state         = Flapjack::Data::State.new(:timestamp => timestamp)
      ncsm_sched_maint  = nil

      if event_condition.nil?
        # Action events represent human or automated interaction with Flapjack
        new_state.action            = event.state
        if old_state && !old_state.condition.nil?
          new_state.condition = old_state.condition
        end
        new_state.condition_changed = false

        Flapjack.redis.multi do |multi|
          multi.hincrby('event_counters', 'action', 1)
          multi.hincrby("event_counters:#{@instance_id}", 'action', 1)
        end
      else
        # Service events represent current state of checks on monitored systems
        Flapjack.redis.multi do |multi|
          if Flapjack::Data::Condition.healthy?(event_condition.name)
            multi.hincrby('event_counters', 'ok', 1)
            multi.hincrby("event_counters:#{@instance_id}", 'ok', 1)
          else
            multi.hincrby('event_counters', 'failure', 1)
            multi.hincrby("event_counters:#{@instance_id}", 'failure', 1)
          end
        end

        new_state = Flapjack::Data::State.new(:timestamp => timestamp)

        if old_state.nil?
          @logger.info { "No previous state for event #{event.id}" }

          if (@ncsm_duration > 0) && !check.id.nil? &&
            (check.tags.all.map(&:name) & @ncsm_ignore_tags).empty?

            @logger.info { "Setting scheduled maintenance for #{time_period_in_words(@ncsm_duration)}" }

            ncsm_sched_maint = Flapjack::Data::ScheduledMaintenance.new(:start_time => timestamp,
              :end_time => timestamp + @ncsm_duration,
              :summary => 'Automatically created for new check')
            ncsm_sched_maint.save

            check.add_scheduled_maintenance(ncsm_sched_maint)
          end

          new_state.condition_changed = true
        else
          new_state.condition_changed = (event_condition.name != old_state.condition)
        end
      end

      new_state.notified = false
      new_state.summary  = event.summary
      new_state.details  = event.details
      new_state.perfdata = event.perfdata

      cond = event_condition.nil? ?
        (old_state.nil? ? nil : old_state.condition) :
        event_condition.name
      new_state.condition = cond unless cond.nil?

      new_state
    end

    def generate_notification(check, old_state, new_state, event, event_condition)
      if [nil, 'acknowledgement'].include?(new_state.action)
        new_state.notified = true
      end

      new_state.save
      check.states << new_state

      severity = if 'test_notifications'.eql?(new_state.action)
        Flapjack::Data::Condition.unhealthy.max_by {|n, pri| pri }.first
      else
        msn = check.most_severe_notification
        msn_cond = msn.nil? ? nil : Flapjack::Data::Condition.for_name(msn.condition)
        if msn_cond.nil? || (!event_condition.nil? && (event_condition.priority > msn_cond.priority))
          check.most_severe_notification = new_state
          new_state.condition
        else
          msn_cond.name
        end
      end

      @logger.debug("Notification is being generated for #{event.id}: " + event.inspect)

      event_hash = (event_condition.nil? || Flapjack::Data::Condition.healthy?(event_condition.name)) ?
        nil : check.ack_hash

      condition_duration = old_state.nil? ? nil :
                             (new_state.timestamp - old_state.timestamp)

      notific = Flapjack::Data::Notification.new(:duration => event.duration,
        :severity => (severity || 'ok'), :condition_duration => condition_duration,
        :event_hash => event_hash, :time => new_state.timestamp)

      notific.save

      new_state.notifications << notific

      @notifier_queue.push(notific)
    end

  end
end
