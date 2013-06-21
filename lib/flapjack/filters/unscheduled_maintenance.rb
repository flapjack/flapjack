#!/usr/bin/env ruby

require 'flapjack/filters/base'

module Flapjack
  module Filters
    class UnscheduledMaintenance
      include Base

      def block?(event)
        result = @persistence.exists("#{event.id}:unscheduled_maintenance") &&
          !event.acknowledgement?
        @log.debug("Filter: Unscheduled Maintenance: #{result ? "block" : "pass"}")
        result
      end
    end
  end
end
