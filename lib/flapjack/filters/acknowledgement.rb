#!/usr/bin/env ruby

require 'flapjack/filters/base'

module Flapjack
  module Filters
    # * If the action event’s state is an acknowledgement, and the corresponding service is in a
    #   failure state, then set unscheduled maintenance for 4 hours on the service
    # * If the action event’s state is an acknowledgement, and the corresponding service is not in a
    #   failure state, then don’t alert
    class Acknowledgement
      include Base

      def block?(event)
        timestamp = Time.now.to_i

        if event.acknowledgement? and @persistence.zscore("failed_services", event.id)
          expiry = 4 * 60 * 60

          # FIXME: need to add summary to summary of existing unscheduled maintenance if there is
          # one, and extend duration / expiry time, instead of creating a separate unscheduled
          # outage as we are doing now...
          #
          # FIXME: also, need to see if a TTL has been provided with the acknowledgement, and use
          # that instead of the default of four hours
          #
          @persistence.setex("#{event.id}:unscheduled_maintenance", expiry, timestamp)
          @persistence.zadd("#{event.id}:unscheduled_maintenances", expiry, timestamp)
          @persistence.set("#{event.id}:#{timestamp}:unscheduled_maintenance:summary", event.summary)
          message = "acknowledgement created for #{event.id}"
          result = false
        else
          message = "no action taken"
          result  = true
        end
        @log.debug("Filter: Acknowledgement: #{result ? "block" : "pass"} (#{message})")
        result
      end
    end
  end
end
