#!/usr/bin/env ruby

require 'flapjack/filters/base'

module Flapjack
  module Filters
    class ScheduledMaintenance
      include Base

      def block?(event, check, previous_state)
        result = check.in_scheduled_maintenance?
        @logger.debug("Filter: Scheduled Maintenance: #{result ? "block" : "pass"}")
        result
      end
    end
  end
end
