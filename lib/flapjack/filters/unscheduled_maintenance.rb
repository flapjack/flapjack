#!/usr/bin/env ruby

require 'flapjack/filters/base'

module Flapjack
  module Filters
    class UnscheduledMaintenance
      include Base

      def block?(event, entity_check, previous_state)
        result = entity_check.in_unscheduled_maintenance? && !event.acknowledgement?
        @logger.debug("Filter: Unscheduled Maintenance: #{result ? "block" : "pass"}")
        result
      end
    end
  end
end
