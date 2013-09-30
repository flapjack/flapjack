#!/usr/bin/env ruby

module Flapjack
  module Data
    class ScheduledMaintenanceR

        include Flapjack::Data::RedisRecord

        define_attributes :start_time => :timestamp,
                          :end_time   => :timestamp,
                          :summary    => :string

        validates :start_time, :presence => true
        validates :end_time, :presence => true

        belongs_to :entity_check, :class_name => 'Flapjack::Data::EntityCheckR'

        def duration
          self.end_time - self.start_time
        end

        # TODO allow summary to be changed as part of the termination
        def finish(time_to_end_at)
          if self.start_time > time_to_end_at

            # the scheduled maintenance period is in the future
            self.entity_check.scheduled_maintenances.delete(self)
            self.destroy

            # scheduled maintenance periods have changed, revalidate
            # TODO don't think this is necessary for the future case
            self.entity_check.update_current_scheduled_maintenance(:revalidate => true)
            return true
          elsif sched_maint.end_time > time_to_end_at
            # it spans the current time, so we'll stop it at that point
            self.end_time = time_to_end_at
            self.save

            # scheduled maintenance periods have changed, revalidate
            self.entity_check.update_current_scheduled_maintenance(:revalidate => true)
            return true
          end

          false
        end

    end
  end
end