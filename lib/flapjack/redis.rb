#!/usr/bin/env ruby

# redis interaction functions for flapjack
# passed in the redis connection that should be used
module Flapjack
  module Redis

    # takes a key "entity:check", returns true if the check is in unscheduled
    # maintenance
    def in_unscheduled_maintenance?(redis, key)
      redis.exists("#{key}:unscheduled_maintenance")
    end

    # returns true if the check is in scheduled maintenance
    def in_scheduled_maintenance?(redis, key)
      redis.exists("#{key}:scheduled_maintenance")
    end

    # returns a hash of all scheduled maintenances for a check
    def scheduled_maintenances(redis, key)
      result = []
      if redis.exists("#{key}:scheduled_maintenances")
        redis.zrange("#{key}:scheduled_maintenances", 0, -1, {:withscores => true}).each {|s|
          puts s.inspect
          start_time = s[0].to_i
          duration   = s[1].to_i
          summary    = redis.get("#{key}:#{start_time}:scheduled_maintenance:summary")
          end_time   = start_time + duration
          result << {:start_time => start_time,
                     :end_time   => end_time,
                     :duration   => duration,
                     :summary    => summary,
                    }
        }
        puts result.inspect
      end
      return result
    end

    # creates a scheduled maintenance period for a check
    def create_scheduled_maintenance(redis, key, opts)
      start_time = opts[:start_time]  # unix timestamp
      duration   = opts[:duration]    # seconds
      summary    = opts[:summary]
      # TODO: consider adding some validation to the data we're adding in here
      # eg start_time is a believable unix timestamp (not in the past and not too
      # far in the future), duration is within some bounds...
      redis.zadd("#{key}:scheduled_maintenances", duration, start_time)
      redis.set("#{key}:#{start_time}:scheduled_maintenance:summary", summary)
    end

    # delete a scheduled maintenance
    def delete_scheduled_maintenance(redis, key, opts)
      start_time = opts[:start_time]
      redis.del("#{key}:#{start_time}:scheduled_maintenance:summary")
      redis.zrem("#{key}:scheduled_maintenances", start_time)
    end

    # creates an event object and adds it to the events list in redis
    #   'entity'    => entity,
    #   'check'     => check,
    #   'type'      => 'service',
    #   'state'     => state,
    #   'summary'   => check_output,
    #   'time'      => timestamp,
    def create_event(redis, event)
      redis.rpush('events', Yajl::Encoder.encode(event))
    end

    def create_acknowledgement(redis, check_id, opts={})
      defaults = {
        'summary' => '...',
      }
      options = defaults.merge(opts)

      entity, check = check_id.split(':')
      event = { 'entity'  => entity,
                'check'   => check,
                'type'    => 'action',
                'state'   => 'acknowledgement',
                'time'    => Time.now.to_i,
                'summary' => options['summary'],
      }
      create_event(redis, event)
    end

  end
end

