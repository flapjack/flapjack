#!/usr/bin/env ruby

require 'flapjack/filters/base'

module Flapjack
  module Filters
    class UnscheduledMaintenance
      include Base

      def block?(check, opts = {})
        old_state = opts[:old_state]
        new_entry = opts[:new_entry]

        result = check.in_unscheduled_maintenance? &&
          !('acknowledgement'.eql?(new_entry.action) ||
            Flapjack::Data::Condition.healthy?(new_entry.condition))

        Flapjack.logger.debug {
          "Filter: Unscheduled Maintenance: #{result ? "block" : "pass"}"
        }

        result
      end

    end
  end
end
