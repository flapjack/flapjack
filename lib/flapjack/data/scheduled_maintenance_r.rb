#!/usr/bin/env ruby

require 'flapjack/data/maintenance_r'

module Flapjack
  module Data
    class ScheduledMaintenanceR < Flapjack::Data::MaintenanceR

        # TODO allow summary to be changed as part of the termination
        def finish(entity_check, time_to_end_at)
          if self.start_time > time_to_end_at

            # the scheduled maintenance period is in the future
            entity_check.scheduled_maintenances.delete(self)
            self.destroy

            # scheduled maintenance periods have changed, revalidate
            # TODO don't think this is necessary for the future case
            entity_check.update_current_scheduled_maintenance(:revalidate => true)
            return true
          elsif sched_maint.end_time > time_to_end_at
            # it spans the current time, so we'll stop it at that point
            self.end_time = time_to_end_at
            self.save

            # scheduled maintenance periods have changed, revalidate
            entity_check.update_current_scheduled_maintenance(:revalidate => true)
            return true
          end

          false
        end

    end
  end
end