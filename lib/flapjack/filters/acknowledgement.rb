#!/usr/bin/env ruby

require 'flapjack/data/check_state'
require 'flapjack/data/unscheduled_maintenance'

require 'flapjack/filters/base'

module Flapjack
  module Filters
    # * If the action event’s state is an acknowledgement, and the corresponding check is in a
    #   failure state, then set unscheduled maintenance for 4 hours on the check
    # * If the action event’s state is an acknowledgement, and the corresponding check is not in a
    #   failure state, then don’t alert
    class Acknowledgement
      include Base

      def block?(event, check, previous_state)
        timestamp = Time.now.to_i

        label = 'Filter: Acknowledgement:'

        return false unless event.type == 'action'

        unless event.acknowledgement?
          @logger.debug("#{label} pass (not an ack)")
          return false
        end

        if check.nil?
          @logger.error "#{label} unknown check for event '#{event.id}'"
          return false
        end

        unless Flapjack::Data::CheckState.failing_states.include?(check.state)
          @logger.debug("#{label} blocking because check '#{check.name}' is not failing")
          return true
        end

        end_time = timestamp + (event.duration || (4 * 60 * 60))

        unsched_maint = Flapjack::Data::UnscheduledMaintenance.new(:start_time => timestamp,
          :end_time => end_time, :summary => event.summary)
        unsched_maint.save

        check.set_unscheduled_maintenance(unsched_maint)

        @logger.debug("#{label} pass (unscheduled maintenance created for #{event.id}, duration: #{end_time - timestamp})")
        false
      end
    end
  end
end
