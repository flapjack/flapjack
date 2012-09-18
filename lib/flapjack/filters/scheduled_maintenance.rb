#!/usr/bin/env ruby

require 'flapjack/filters/base'

module Flapjack
  module Filters
    class ScheduledMaintenance
      include Base

      def block?(event)
        result = @persistence.exists("#{event.id}:scheduled_maintenance")
        @log.debug("Filter: Scheduled Maintenance: #{result ? "block" : "pass"}")
        result
      end
    end
  end
end
