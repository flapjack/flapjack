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

        unless Flapjack::Data::CheckStateR.failing_states.include?(entity_check.state)
          @logger.debug("#{label} blocking because check '#{entity_check.name}' on entity '#{entity_check.entity_name}' is not failing")
          return true
        end

        end_time = timestamp + (event.duration || (4 * 60 * 60))

        unsched_maint = Flapjack::Data::UnscheduledMaintenanceR.new(:start_time => timestamp,
          :end_time => end_time, :summary => event.summary)
        unsched_maint.save

        entity_check.set_unscheduled_maintenance(unsched_maint)

        @logger.debug("#{label} pass (unscheduled maintenance created for #{event.id}, duration: #{end_time - timestamp})")
        false
      end
    end
  end
end
