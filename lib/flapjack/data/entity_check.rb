#!/usr/bin/env ruby

require 'yajl/json_gem'

require 'flapjack/data/entity'

module Flapjack

  module Data

    class EntityCheck

      STATE_OK              = 'ok'
      STATE_WARNING         = 'warning'
      STATE_CRITICAL        = 'critical'
      STATE_ACKNOWLEDGEMENT = 'acknowledgement'
      STATE_UNKNOWN         = 'unknown'

      attr_accessor :entity, :check

      def self.for_event_id(event_id, options = {})
        redis = options[:redis]
        entity_name, check = event_id.split(':')
        entity = Flapjack::Data::Entity.find_by_name(entity_name, :redis => redis)
        return nil unless entity && entity.is_a?(Flapjack::Data::Entity)
        self.new(entity, check, :redis => redis)
      end

      def self.for_entity_name(entity_name, check, options = {})
        redis = options[:redis]
        entity = Flapjack::Data::Entity.find_by_name(entity_name, :redis => redis)
        return nil unless entity && entity.is_a?(Flapjack::Data::Entity)
        self.new(entity, check, :redis => redis)
      end

      def self.for_entity_id(entity_id, check, options = {})
        redis = options[:redis]
        entity = Flapjack::Data::Entity.find_by_id(entity_id, :redis => redis)
        return nil unless entity && entity.is_a?(Flapjack::Data::Entity)
        self.new(entity, check, :redis => redis)
      end

      def self.for_entity(entity, check, options = {})
        redis = options[:redis]
        return nil unless entity && entity.is_a?(Flapjack::Data::Entity)
        self.new(entity, check, :redis => redis)
      end

      # takes a key "entity:check", returns true if the check is in unscheduled
      # maintenance
      def in_unscheduled_maintenance?
        @redis.exists("#{@key}:unscheduled_maintenance")
      end

      # returns true if the check is in scheduled maintenance
      def in_scheduled_maintenance?
        @redis.exists("#{@key}:scheduled_maintenance")
      end

      # creates an event object and adds it to the events list in redis
      #   'type'      => 'service',
      #   'state'     => state,
      #   'summary'   => check_output,
      #   'time'      => timestamp
      def create_event(event)
        event.merge!('entity' => @entity.name, 'check' => @check)
        event['time'] = Time.now.to_i if event['time'].nil?
        @redis.rpush('events', Yajl::Encoder.encode(event))
      end

      def create_acknowledgement(opts = {})
        defaults = {
          :summary => '...'
        }
        options = defaults.merge(opts)

        event = { 'type'    => 'action',
                  'state'   => 'acknowledgement',
                  'summary' => options['summary']
                }
        create_event(event)
      end

      # returns an array of all unscheduled maintenances for a check
      def unscheduled_maintenances
        maintenances(:scheduled => false)
      end

      # returns an array of all scheduled maintenances for a check
      def scheduled_maintenances
        maintenances(:scheduled => true)
      end

      # creates a scheduled maintenance period for a check
      def create_scheduled_maintenance(opts = {})
        start_time = opts[:start_time]  # unix timestamp
        duration   = opts[:duration]    # seconds
        summary    = opts[:summary]
        # TODO: consider adding some validation to the data we're adding in here
        # eg start_time is a believable unix timestamp (not in the past and not too
        # far in the future), duration is within some bounds...
        @redis.zadd("#{@key}:scheduled_maintenances", duration, start_time)
        @redis.set("#{@key}:#{start_time}:scheduled_maintenance:summary", summary)

        # scheduled maintenance periods have changed, revalidate
        update_scheduled_maintenance(:revalidate => true)
      end

      # delete a scheduled maintenance
      def delete_scheduled_maintenance(opts = {})
        start_time = opts[:start_time]
        @redis.del("#{@key}:#{start_time}:scheduled_maintenance:summary")
        @redis.zrem("#{@key}:scheduled_maintenances", start_time)

        # scheduled maintenance periods have changed, revalidate
        update_scheduled_maintenance(:revalidate => true)
      end

      # if not in scheduled maintenance, looks in scheduled maintenance list for a check to see if
      # current state should be set to scheduled maintenance, and sets it as appropriate
      def update_scheduled_maintenance(opts = {})
        if opts[:revalidate]
          @redis.del("#{@key}:scheduled_maintenance")
        else
          return if in_scheduled_maintenance?
        end

        # are we within a scheduled maintenance period?
        t = Time.now.to_i
        current_sched_ms = scheduled_maintenances.select {|sm|
          (sm[:start_time] <= t) && (t < sm[:end_time])
        }
        return if current_sched_ms.empty?

        # yes! so set current scheduled maintenance
        # if multiple scheduled maintenances found, find the end_time furthest in the future
        most_futuristic = current_sched_ms.max {|sm| sm[:end_time] }
        start_time = most_futuristic[:start_time]
        duration   = most_futuristic[:duration]
        @redis.setex("#{@key}:scheduled_maintenance", duration, start_time)
      end

      # should this return STATE_UNKNOWN if nil?
      def state
        @redis.hget("check:#{@key}", 'state')
      end

      # FIXME: clientx -- possibly an initialised @client value instead?
      def state=(state = STATE_OK)
        return unless validate_state(state)
        t = Time.now.to_i - (60*60*24)
        @redis.hset("check:#{@key}", 'state', state)
        @redis.hset("check:#{@key}", 'last_change', t)
        if STATE_CRITICAL.eql?(state)
          @redis.zadd('failed_checks', t, @key)
          @redis.zadd('failed_checks:client:clientx', t, @key)
        elsif STATE_OK.eql?(state)
          @redis.zrem('failed_checks', @key)
          @redis.zrem('failed_checks:client:clientx', @key)
        end
      end

      def last_update
        @redis.hget("check:#{@key}", 'last_update').to_i
      end

      def last_change
        @redis.hget("check:#{@key}", 'last_change').to_i
      end

      def last_problem_notification
        @redis.get("#{@key}:last_problem_notification").to_i
      end

      def last_recovery_notification
        @redis.get("#{@key}:last_recovery_notification").to_i
      end

      def last_acknowledgement_notification
        @redis.get("#{@key}:last_acknowledgement_notification").to_i
      end

      def failed?
        ['warning', 'critical'].include?( state )
      end

      def duration_of_current_failure
        return unless failed?
        Time.now.to_i - @redis.hget("check:#{@key}", 'last_change').to_i
      end

      def summary
        timestamp = @redis.lindex("#{@key}:states", -1)
        @redis.get("#{@key}:#{timestamp}:summary")
      end

      def time_since_last_problem_alert
        result = Time.now.to_i - @redis.get("#{@key}:last_problem_notification").to_i
        # @log.debug("Filter: Delays: time_since_last_problem_alert is returning #{result}")
        result
      end

      def time_since_last_alert_about_current_problem
        return unless failed?
        result = time_since_last_problem_alert
        return unless (result < duration_of_current_failure)
        # if @logger
          # @logger.debug("Filter: Delays: time_since_last_alert_about_current_problem is returning #{result}")
        # end
        result
      end

    private

      # Passing around the redis handle like this is a SMELL.
      def initialize(entity, check, options = {})
        raise "Redis connection not set" unless @redis = options[:redis]
        @entity = entity
        @check = check
        @key = "#{entity.name}:#{check}" if entity && check
      end

      def validate_state(state)
        [STATE_OK, STATE_WARNING, STATE_CRITICAL,
         STATE_ACKNOWLEDGEMENT, STATE_UNKNOWN].include?(state)
      end

      def maintenances(opts = {})
        sched = opts[:scheduled] ? 'scheduled' : 'unscheduled'
        return [] unless @redis.exists("#{@key}:#{sched}_maintenances")
        @redis.zrange("#{@key}:#{sched}_maintenances", 0, -1, :withscores => true).collect {|s|
          start_time = s[0].to_i
          duration   = s[1].to_i
          summary    = @redis.get("#{@key}:#{start_time}:#{sched}_maintenance:summary")
          end_time   = start_time + duration
          {:start_time => start_time,
           :end_time   => end_time,
           :duration   => duration,
           :summary    => summary
          }
        }
      end

    end

  end

end
