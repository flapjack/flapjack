#!/usr/bin/env ruby

require 'flapjack/filters/base'

module Flapjack
  module Filters
    class ScheduledMaintenance
      include Base

      def block?(event, entity_check, previous_state)
        result = entity_check.in_scheduled_maintenance?
        @logger.debug("Filter: Scheduled Maintenance: #{result ? "block" : "pass"}")
        result
      end
    end
  end
end
