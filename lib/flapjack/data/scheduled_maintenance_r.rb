#!/usr/bin/env ruby

require 'flapjack/data/maintenance_r'

module Flapjack
  module Data
    class ScheduledMaintenanceR < Flapjack::Data::MaintenanceR

  #     # creates a scheduled maintenance period for a check
  #     # TODO: consider adding some validation to the data we're adding in here
  #     # eg start_time is a believable unix timestamp (not in the past and not too
  #     # far in the future), duration is within some bounds...
  #     def create_scheduled_maintenance(start_time, duration, opts = {})
  #       raise ArgumentError, 'start time must be provided as a Unix timestamp' unless start_time && start_time.is_a?(Integer)
  #       raise ArgumentError, 'duration in seconds must be provided' unless duration && duration.is_a?(Integer) && (duration > 0)

  #       summary = opts[:summary]
  #       Flapjack.redis.zadd("#{@key}:scheduled_maintenances", duration, start_time)
  #       Flapjack.redis.set("#{@key}:#{start_time}:scheduled_maintenance:summary", summary)

  #       Flapjack.redis.zadd("#{@key}:sorted_scheduled_maintenance_timestamps", start_time, start_time)

  #       # scheduled maintenance periods have changed, revalidate
  #       update_current_scheduled_maintenance(:revalidate => true)
  #     end

  #     # if not in scheduled maintenance, looks in scheduled maintenance list for a check to see if
  #     # current state should be set to scheduled maintenance, and sets it as appropriate
  #     def update_current_scheduled_maintenance(opts = {})
  #       if opts[:revalidate]
  #         Flapjack.redis.del("#{@key}:scheduled_maintenance")
  #       else
  #         return if in_scheduled_maintenance?
  #       end

  #       # are we within a scheduled maintenance period?
  #       current_time = Time.now.to_i
  #       current_sched_ms = maintenances(nil, nil, :scheduled => true).select {|sm|
  #         (sm[:start_time] <= current_time) && (current_time < sm[:end_time])
  #       }
  #       return if current_sched_ms.empty?

  #       # yes! so set current scheduled maintenance
  #       # if multiple scheduled maintenances found, find the end_time furthest in the future
  #       most_futuristic = current_sched_ms.max {|sm| sm[:end_time] }
  #       start_time = most_futuristic[:start_time]
  #       duration   = most_futuristic[:duration]
  #       Flapjack.redis.setex("#{@key}:scheduled_maintenance", duration.to_i, start_time)
  #     end

  #     # TODO allow summary to be changed as part of the termination
  #     def end_scheduled_maintenance(start_time)
  #       raise ArgumentError, 'start time must be supplied as a Unix timestamp' unless start_time && start_time.is_a?(Integer)

  #       # don't do anything if a scheduled maintenance period with that start time isn't stored
  #       duration = Flapjack.redis.zscore("#{@key}:scheduled_maintenances", start_time)
  #       return false if duration.nil?

  #       current_time = Time.now.to_i

  #       if start_time > current_time
  #         # the scheduled maintenance period (if it exists) is in the future
  #         Flapjack.redis.del("#{@key}:#{start_time}:scheduled_maintenance:summary")
  #         Flapjack.redis.zrem("#{@key}:scheduled_maintenances", start_time)

  #         Flapjack.redis.zremrangebyscore("#{@key}:sorted_scheduled_maintenance_timestamps", start_time, start_time)

  #         # scheduled maintenance periods (may) have changed, revalidate
  #         update_current_scheduled_maintenance(:revalidate => true)

  #         return true
  #       elsif (start_time + duration) > current_time
  #         # it spans the current time, so we'll stop it at that point
  #         new_duration = current_time - start_time
  #         Flapjack.redis.zadd("#{@key}:scheduled_maintenances", new_duration, start_time)

  #         # scheduled maintenance periods have changed, revalidate
  #         update_current_scheduled_maintenance(:revalidate => true)

  #         return true
  #       end

  #       false
  #     end

    end
  end
end