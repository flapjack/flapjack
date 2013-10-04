#!/usr/bin/env ruby

require 'flapjack/filters/base'

module Flapjack
  module Filters
    # * If the action event’s state is an acknowledgement, and the corresponding check is in a
    #   failure state, then set unscheduled maintenance for 4 hours on the check
    # * If the action event’s state is an acknowledgement, and the corresponding check is not in a
    #   failure state, then don’t alert
    class Acknowledgement
      include Base

      def block?(event, entity_check, previous_state)
        timestamp = Time.now.to_i

        label = 'Filter: Acknowledgement:'

        return false unless event.type == 'action'

        unless event.acknowledgement?
          @logger.debug("#{label} pass (not an ack)")
          return false
        end

        if entity_check.nil?
          @logger.error "#{label} unknown entity for event '#{event.id}'"
          return false
        end

        entity_name, check_name = event_id.split(':', 2);

        check_is_failing = EntityCheckR.
          union(:state => Flapjack::Data::CheckStateR.failing_states).
          intersect(:entity_name => entity_name, :name => check_name).count > 0

        unless check_is_failing
          @logger.debug("#{label} blocking because zscore of failed_checks for #{event.id} is false")
          return true
        end

        end_time = timestamp + (event.duration || (4 * 60 * 60))

        unsched_maint = Flapjack::Data::UnscheduledMaintenanceR.new(:start_time => timestamp,
          :end_time => end_time, :summary => event.summary)
        unsched_maint.save

        entity_check.set_unscheduled_maintenance(unsched_maint)

        @logger.debug("#{label} pass (unscheduled maintenance created for #{event.id}, duration: #{um_duration})")
        false
      end
    end
  end
end
