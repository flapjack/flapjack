#!/usr/bin/env ruby

require 'flapjack/filters/base'

module Flapjack
  module Filters
    class UnscheduledMaintenance
      include Base

      def block?(event)
        result = Flapjack.redis.exists("#{event.id}:unscheduled_maintenance") &&
          !event.acknowledgement?
        @logger.debug("Filter: Unscheduled Maintenance: #{result ? "block" : "pass"}")
        result
      end
    end
  end
end
