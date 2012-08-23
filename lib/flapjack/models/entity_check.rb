#!/usr/bin/env ruby

module Flapjack

  module Data

    class EntityCheck

      STATE_OK              = 'ok'
      STATE_WARNING         = 'warning'
      STATE_CRITICAL        = 'critical'
      STATE_ACKNOWLEDGEMENT = 'acknowledgement'
      STATE_UP              = 'up'
      STATE_DOWN            = 'down'
      STATE_UNKNOWN         = 'unknown'

      def initialize(options = {})
        raise "Redis connection not set" unless @redis = options[:redis]
        raise "Entity not set" unless @entity = options[:entity]
        raise "Check not set" unless @check = options[:check]
        @key = "#{@entity}:#{@check}"
        @logger = options[:logger]
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
      #   'entity'    => entity,
      #   'check'     => check,
      #   'type'      => 'service',
      #   'state'     => state,
      #   'summary'   => check_output,
      #   'time'      => timestamp
      def create_event(event)
        event.merge('entity' => @entity, 'check' => @check)
        event.time = Time.now.to_i if event.time.nil?
        @redis.rpush('events', Yajl::Encoder.encode(event))
      end

      def create_acknowledgement(opts = {})
        defaults = {
          :summary => '...'
        }
        options = defaults.merge(opts)

        event = { 'entity'  => @entity,
                  'check'   => @check,
                  'type'    => 'action',
                  'state'   => 'acknowledgement',
                  'summary' => options['summary']
                }
        create_event(event)
      end

      # returns an array of all scheduled maintenances for a check
      def scheduled_maintenances
        result = []
        if @redis.exists("#{@key}:scheduled_maintenances")
          @redis.zrange("#{@key}:scheduled_maintenances", 0, -1, {:withscores => true}).each {|s|
            puts s.inspect
            start_time = s[0].to_i
            duration   = s[1].to_i
            summary    = @redis.get("#{@key}:#{start_time}:scheduled_maintenance:summary")
            end_time   = start_time + duration
            result << {:start_time => start_time,
                       :end_time   => end_time,
                       :duration   => duration,
                       :summary    => summary,
                      }
          }
          puts result.inspect
        end
        result
      end

      # creates a scheduled maintenance period for a check
      def create_scheduled_maintenance(opts)
        start_time = opts[:start_time]  # unix timestamp
        duration   = opts[:duration]    # seconds
        summary    = opts[:summary]
        # TODO: consider adding some validation to the data we're adding in here
        # eg start_time is a believable unix timestamp (not in the past and not too
        # far in the future), duration is within some bounds...
        @redis.zadd("#{@key}:scheduled_maintenances", duration, start_time)
        @redis.set("#{@key}:#{start_time}:scheduled_maintenance:summary", summary)
      end

      # delete a scheduled maintenance
      def delete_scheduled_maintenance(opts)
        start_time = opts[:start_time]
        @redis.del("#{@key}:#{start_time}:scheduled_maintenance:summary")
        @redis.zrem("#{@key}:scheduled_maintenances", start_time)
        @redis.del("#{@key}:scheduled_maintenance")
        update_scheduled_maintenance
      end

      # if not in scheduled maintenance, looks in scheduled maintenance list for a check to see if
      # current state should be set to scheduled maintenance, and sets it as appropriate
      def update_scheduled_maintenance
        return if in_scheduled_maintenance?

        # are we within a scheduled maintenance period?
        t = Time.now.to_i
        current_sched_ms = scheduled_maintenances.select {|sm|
          (sm[:start_time] <= t) && (t < sm[:end_time])
        }
        return if current_sched_ms.empty?

        # yes! so set current scheduled maintenance
        # if multiple scheduled maintenances found, find the end_time furthest in the future
        futurist = current_sched_ms.max {|sm| sm[:start_time] }
        start_time = futurist[:start_time]
        duration   = futurist[:duration]
        @redis.setex("#{@key}:scheduled_maintenance", duration, start_time)
      end

      # FIXME: clientx -- possibly an initialised @client value instead?
      # FIXME: include STATE_UP & STATE_DOWN ??
      def state=(state = STATE_OK)
        return unless validate_state(state)
        t = Time.now.to_i - (60*60*24)
        @redis.hset(@key, 'state', e_state)
        @redis.hset(@key, 'last_change', t)
        if STATE_CRITICAL.eql?(state)
          @redis.zadd('failed_checks', t, entity_check)
          @redis.zadd('failed_checks:client:clientx', t, entity_check)
        elsif STATE_OK.eql?(state)
          @redis.zrem('failed_checks', entity_check)
          @redis.zrem('failed_checks:client:clientx', entity_check)
        end
      end

      def status
        {:state                       => @redis.hget(@key, 'state'),
         :last_update                 => @redis.hget(@key, 'last_update'),
         :last_change                 => @redis.hget(@key, 'last_change'),
         :summary                     => summary,
         :last_notifications          => last_notifications,
         :in_unscheduled_maintenance  => in_unscheduled_maintenance?,
         :in_scheduled_maintenance    => in_scheduled_maintenance?
        }
      end

      def last_notifications
        {:problem          => @redis.get("#{@key}:last_problem_notification").to_i,
         :recovery         => @redis.get("#{@key}:last_recovery_notification").to_i,
         :acknowledgement  => @redis.get("#{@key}:last_acknowledgement_notification").to_i
        }
      end

      def summary
        @redis.multi do
          timestamp = @redis.lindex("#{@key}:states", -1)
          @redis.get("#{@key}:#{timestamp}:summary")
        end
      end

    private

      def validate_state(state)
        return if [STATE_OK, STATE_WARNING, STATE_CRITICAL,
                   STATE_ACKNOWLEDGEMENT, STATE_UP, STATE_DOWN,
                   STATE_UNKNOWN].include?(state)
        if @logger
          @logger.error "Invalidate state value #{state}"
        end
      end

    end

  end

end
