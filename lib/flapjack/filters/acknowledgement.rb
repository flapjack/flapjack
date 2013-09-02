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

        unless @redis.zscore("failed_checks", event.id)
          @logger.debug("#{label} blocking because zscore of failed_checks for #{event.id} is false")
          return true
        end

        entity_check.create_unscheduled_maintenance(timestamp,
          (event.duration || (4 * 60 * 60)),
          :summary  => event.summary)

        @logger.debug("#{label} pass (unscheduled maintenance created for #{event.id})")
        false
      end
    end
  end
end
