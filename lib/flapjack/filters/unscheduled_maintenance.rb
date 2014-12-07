#!/usr/bin/env ruby

require 'flapjack/filters/base'

module Flapjack
  module Filters
    class UnscheduledMaintenance
      include Base

      def block?(event, check, opts = {})
        new_state = opts[:new_state]
        result = check.in_unscheduled_maintenance? &&
          !('acknowledgement'.eql?(new_state.action))

        @logger.debug {
          "Filter: Unscheduled Maintenance: #{result ? "block" : "pass"}"
        }

        result
      end

    end
  end
end
