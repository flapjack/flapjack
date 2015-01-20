#!/usr/bin/env ruby

require 'chronic_duration'

require 'em-hiredis'

require 'flapjack/filters/acknowledgement'
require 'flapjack/filters/ok'
require 'flapjack/filters/scheduled_maintenance'
require 'flapjack/filters/unscheduled_maintenance'
require 'flapjack/filters/delays'

require 'flapjack/data/entity_check'
require 'flapjack/data/event'
require 'flapjack/redis_pool'
require 'flapjack/utility'

module Flapjack

  class Processor

    include Flapjack::Utility

    def initialize(opts = {})
      @config = opts[:config]
      @redis_config = opts[:redis_config] || {}
      @logger = opts[:logger]

      @redis = Flapjack::RedisPool.new(:config => @redis_config, :size => 2, :logger => @logger)

      @queue = @config['queue'] || 'events'

      @notifier_queue = @config['notifier_queue'] || 'notifications'

      @archive_events        = @config['archive_events'] || false
      @events_archive_maxage = @config['events_archive_maxage']

      ncsm_duration_conf = @config['new_check_scheduled_maintenance_duration'] || '100 years'
      @ncsm_duration = ChronicDuration.parse(ncsm_duration_conf, :keep_zero => true)

      @ncsm_ignore_tags = @config['new_check_scheduled_maintenance_ignore_tags'] || []

      @exit_on_queue_empty = !! @config['exit_on_queue_empty']

      options = { :logger => opts[:logger], :redis => @redis }
      @filters = []
      @filters << Flapjack::Filters::Ok.new(options)
      @filters << Flapjack::Filters::ScheduledMaintenance.new(options)
      @filters << Flapjack::Filters::UnscheduledMaintenance.new(options)
      @filters << Flapjack::Filters::Delays.new(options)
      @filters << Flapjack::Filters::Acknowledgement.new(options)

      boot_time     = opts[:boot_time]
      fqdn          = `/bin/hostname -f`.chomp
      pid           = Process.pid
      @instance_id  = "#{fqdn}:#{pid}"

      # FIXME: all of the below keys assume there is only ever one executive running;
      # we could generate a fuid and save it to disk, and prepend it from that
      # point on...

      # FIXME: add an administrative function to reset all event counters

      @redis.hset('event_counters', 'all', 0)     if @redis.hget('event_counters', 'all').nil?
      @redis.hset('event_counters', 'ok', 0)      if @redis.hget('event_counters', 'ok').nil?
      @redis.hset('event_counters', 'failure', 0) if @redis.hget('event_counters', 'failure').nil?
      @redis.hset('event_counters', 'action', 0)  if @redis.hget('event_counters', 'action').nil?
      @redis.hset('event_counters', 'invalid', 0) if @redis.hget('event_counters', 'invalid').nil?

      @redis.hset("executive_instance:#{@instance_id}", 'boot_time', boot_time.to_i)
      @redis.hset("event_counters:#{@instance_id}", 'all', 0)
      @redis.hset("event_counters:#{@instance_id}", 'ok', 0)
      @redis.hset("event_counters:#{@instance_id}", 'failure', 0)
      @redis.hset("event_counters:#{@instance_id}", 'action', 0)
      @redis.hset("event_counters:#{@instance_id}", 'invalid', 0)
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
        event = Flapjack::Data::Event.next(@queue,
                                           :redis => @redis,
                                           :archive_events => @archive_events,
                                           :events_archive_maxage => @events_archive_maxage,
                                           :logger => @logger,
                                           :block => ! @exit_on_queue_empty )
        if @exit_on_queue_empty && event.nil? && Flapjack::Data::Event.pending_count(@queue, :redis => @redis)
          # SHUT IT ALL DOWN!!!
          @logger.warn "Shutting down as exit_on_queue_empty is true, and the queue is empty"
          Process.kill('INT', Process.pid)
          break
        end

        if event.nil?
          @redis.hincrby('event_counters', 'all', 1)
          @redis.hincrby("event_counters:#{@instance_id}", 'all', 1)
          @redis.hincrby('event_counters', 'invalid', 1)
          @redis.hincrby("event_counters:#{@instance_id}", 'invalid', 1)
        else
          process_event(event)
        end
      end

      @logger.info("Exiting main loop.")
    end

    # this must use a separate connection to the main Executive one, as it's running
    # from a different fiber while the main one is blocking.
    def stop
      unless @should_quit
        @should_quit = true
        redis_uri = @redis_config[:path] ||
          "redis://#{@redis_config[:host] || '127.0.0.1'}:#{@redis_config[:port] || '6379'}/#{@redis_config[:db] || '0'}"
        shutdown_redis = EM::Hiredis.connect(redis_uri)
        shutdown_redis.rpush('events', Flapjack.dump_json('type' => 'noop'))
      end
    end

  private

    def process_event(event)
      pending = Flapjack::Data::Event.pending_count(@queue, :redis => @redis)
      @logger.debug("#{pending} events waiting on the queue")
      @logger.debug("Raw event received: #{event.inspect}")

      if ('noop' == event.type)
        return
      end

      event_str = "#{event.id}, #{event.type}, #{event.state}, #{event.summary}"
      event_str << ", #{Time.at(event.time).to_s}" if event.time
      @logger.debug("Processing Event: #{event_str}")

      entity_check = Flapjack::Data::EntityCheck.for_event_id(event.id, :create_entity => true, :redis => @redis)
      timestamp = Time.now.to_i

      event.tags = (event.tags || Set.new) + entity_check.tags

      should_notify, previous_state = update_keys(event, entity_check, timestamp)

      if !should_notify
        @logger.debug("Not generating notification for event #{event.id} because filtering was skipped")
        return
      elsif blocker = @filters.find {|filter| filter.block?(event, entity_check, previous_state) }
        @logger.debug("Not generating notification for event #{event.id} because this filter blocked: #{blocker.name}")
        return
      end

      @logger.info("Generating notification for event #{event_str}")
      generate_notification(event, entity_check, timestamp, previous_state)
    end

    def update_keys(event, entity_check, timestamp)
      # TODO: run touch_keys from a separate EM timer for efficiency
      touch_keys

      result = true
      previous_state = nil

      event.counter = @redis.hincrby('event_counters', 'all', 1)
      @redis.hincrby("event_counters:#{@instance_id}", 'all', 1)

      # FIXME skip if entity_check.nil?

      # FIXME: validate that the event is sane before we ever get here
      # FIXME: create an event if there is dodgy data

      case event.type
      # Service events represent current state of checks on monitored systems
      when 'service'
        if event.failure?
          # ensure that the check's hash is stored for later lookup
          # can't happen inside the multi as it must get a value
          event.id_hash = entity_check.ack_hash
        end

        @redis.multi do |multi|
          if event.ok?
            multi.hincrby('event_counters', 'ok', 1)
            multi.hincrby("event_counters:#{@instance_id}", 'ok', 1)
          elsif event.failure?
            multi.hincrby('event_counters', 'failure', 1)
            multi.hincrby("event_counters:#{@instance_id}", 'failure', 1)
          else
            multi.hincrby('event_counters', 'invalid', 1)
            multi.hincrby("event_counters:#{@instance_id}", 'invalid', 1)
            @logger.error("Invalid event received: #{event.inspect}")
          end
        end

        previous_state = entity_check.state

        if previous_state.nil?
          @logger.info("No previous state for event #{event.id}")

          if @ncsm_duration > 0 && (event.tags & @ncsm_ignore_tags).empty?
            @logger.info("Setting scheduled maintenance for #{time_period_in_words(@ncsm_duration)}")
            entity_check.create_scheduled_maintenance(timestamp,
              @ncsm_duration, :summary => 'Automatically created for new check')
          end

          # If the service event's state is ok and there was no previous state, don't alert.
          # This stops new checks from alerting as "recovery" after they have been added.
          if event.ok?
            @logger.debug("setting skip_filters to true because there was no previous state and event is ok")
            result = false
          end
        end

        entity_check.update_state(event.state, :timestamp => timestamp,
                                  :summary => event.summary, :count => event.counter,
                                  :details => event.details, :perfdata => event.perfdata,
                                  :initial_failure_delay => event.initial_failure_delay,
                                  :repeat_failure_delay => event.repeat_failure_delay)

        entity_check.update_current_scheduled_maintenance

      # Action events represent human or automated interaction with Flapjack
      when 'action'
        # When an action event is processed, store the event.
        @redis.multi do |multi|
          multi.hset(event.id + ':actions', timestamp, event.state)
          multi.hincrby('event_counters', 'action', 1)
          multi.hincrby("event_counters:#{@instance_id}", 'action', 1)
        end
      else
        @redis.multi do |multi|
          multi.hincrby('event_counters', 'invalid', 1)
          multi.hincrby("event_counters:#{@instance_id}", 'invalid', 1)
        end
        @logger.error("Invalid event received: #{event.inspect}")
      end

      [result, previous_state]
    end

    def generate_notification(event, entity_check, timestamp, previous_state)
      notification_type = Flapjack::Data::Notification.type_for_event(event)
      max_notified_severity = entity_check.max_notified_severity_of_current_failure

      @redis.multi do |multi|
        multi.set("#{event.id}:last_#{notification_type}_notification", timestamp)
        multi.set("#{event.id}:last_#{event.state}_notification", timestamp) if event.failure?
        multi.rpush("#{event.id}:#{notification_type}_notifications", timestamp)
        multi.rpush("#{event.id}:#{event.state}_notifications", timestamp) if event.failure?
      end

      @logger.debug("Notification of type #{notification_type} is being generated for #{event.id}: " + event.inspect)

      severity = Flapjack::Data::Notification.severity_for_event(event, max_notified_severity)

      lc = entity_check.last_change
      state_duration = lc ? (timestamp - lc) : nil

      Flapjack::Data::Notification.add(@notifier_queue, event,
        :type => notification_type, :severity => severity,
        :last_state => previous_unique_state(entity_check), :state_duration => state_duration,
        :redis => @redis)
    end

    def previous_unique_state(entity_check)
      hs = entity_check.historical_states(nil, nil, :order => 'desc', :limit => 2)
      return { :last_state => nil, :last_summary => nil } unless hs.length == 2
      return hs.last
    end

  end
end
