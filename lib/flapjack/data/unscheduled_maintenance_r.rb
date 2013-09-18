#!/usr/bin/env ruby

require 'flapjack/data/maintenance_r'

module Flapjack
  module Data
    class UnscheduledMaintenanceR < MaintenanceR

  #     def create_unscheduled_maintenance(start_time, duration, opts = {})
  #       raise ArgumentError, 'start time must be provided as a Unix timestamp' unless start_time && start_time.is_a?(Integer)
  #       raise ArgumentError, 'duration in seconds must be provided' unless duration && duration.is_a?(Integer) && (duration > 0)

  #       summary    = opts[:summary]
  #       time_remaining = (start_time + duration) - Time.now.to_i
  #       if time_remaining > 0
  #         end_unscheduled_maintenance(start_time) if in_unscheduled_maintenance?
  #         Flapjack.redis.setex("#{@key}:unscheduled_maintenance", time_remaining, start_time)
  #       end
  #       Flapjack.redis.zadd("#{@key}:unscheduled_maintenances", duration, start_time)
  #       Flapjack.redis.set("#{@key}:#{start_time}:unscheduled_maintenance:summary", summary)

  #       Flapjack.redis.zadd("#{@key}:sorted_unscheduled_maintenance_timestamps", start_time, start_time)
  #     end

  #     # ends any unscheduled maintenance
  #     def end_unscheduled_maintenance(end_time)
  #       raise ArgumentError, 'end time must be provided as a Unix timestamp' unless end_time && end_time.is_a?(Integer)

  #       if (um_start = Flapjack.redis.get("#{@key}:unscheduled_maintenance"))
  #         duration = end_time - um_start.to_i
  #         @logger.debug("ending unscheduled downtime for #{@key} at #{Time.at(end_time).to_s}") if @logger
  #         Flapjack.redis.del("#{@key}:unscheduled_maintenance")
  #         Flapjack.redis.zadd("#{@key}:unscheduled_maintenances", duration, um_start) # updates existing UM 'score'
  #       else
  #         @logger.debug("end_unscheduled_maintenance called for #{@key} but none found") if @logger
  #       end
  #     end

    end
  end
end