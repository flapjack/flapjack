#!/usr/bin/env ruby

module Flapjack

  module Data

    class EntityCheck

      STATE_OK              = 'ok'
      STATE_WARNING         = 'warning'
      STATE_CRITICAL        = 'critical'
      STATE_ACKNOWLEDGEMENT = 'acknowledgement'
      STATE_UNKNOWN         = 'unknown'

      def initialize(options = {})
        raise "Redis connection not set" unless @redis = options[:redis]
        raise "Name not set" unless @name = options[:name]
        raise "Check not set" unless @check = options[:check]
        @key = "#{@name}:#{@check}"
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
        event.merge('entity' => @name, 'check' => @check)
        event.time = Time.now.to_i if event.time.nil?
        @redis.rpush('events', Yajl::Encoder.encode(event))
      end

      def create_acknowledgement(opts = {})
        defaults = {
          'summary' => '...'
        }
        options = defaults.merge(opts)

        event = { 'entity'  => @name,
                  'check'   => @check,
                  'type'    => 'action',
                  'state'   => 'acknowledgement',
                  'summary' => options['summary']
                }
        create_event(event)
      end

      def set_scheduled_maintenance(reason, duration = 60*60*2)
        t = Time.now.to_i
        @redis.setex("#{@key}:scheduled_maintenance", duration, t)
        @redis.zadd("#{@key}:scheduled_maintenances", duration, t)
        @redis.set("#{@key}:#{t}:scheduled_maintenance:summary", reason)
      end

      def remove_scheduled_maintenance
        @redis.del("#{entity_check}:scheduled_maintenance")
      end

      # end any unscheduled downtime
      def remove_unscheduled_maintenance
        if (um_start = @redis.get("#{@key}:unscheduled_maintenance"))
          @redis.del("#{@key}:unscheduled_maintenance")
          duration = Time.now.to_i - um_start.to_i
          @redis.zadd("#{@key}:unscheduled_maintenances", duration, um_start)
        end
      end

      # FIXME: clientx -- possibly an initialised @client value instead?
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
         :summary                     => check_summary,
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

      def last_notification
        last_notifications.sort_by {|kind, timestamp| timestamp}.last
      end

      def check_summary
        timestamp = @redis.lindex("#{@key}:states", -1)
        @redis.get("#{@key}:#{timestamp}:summary")
      end

    private

      def validate_state(state)
        return if [STATE_OK, STATE_WARNING, STATE_CRITICAL,
                   STATE_ACKNOWLEDGEMENT, STATE_UNKNOWN].include?(state)
        if @logger
          @logger.error "Invalidate state value #{state}"
        end
      end

    end

  end

end
