#!/usr/bin/env ruby

require 'flapjack/filters/base'

module Flapjack
  module Filters

    # * If the service event’s state is ok and the previous state was ok, don’t alert
    # * If the service event's state is ok and there is unscheduled downtime set, end the unscheduled
    #   downtime
    class Ok
      include Base

      def block?(event)
        result = true

        if event.ok?

          if not (@persistence.hget(event.id, 'state') == 'ok')
            result = false
          end

          # end any unscheduled downtime
          if (um_start = @persistence.get("#{event.id}:unscheduled_maintenance"))
            @persistence.del("#{event.id}:unscheduled_maintenance")
            duration = Time.now.to_i - um_start.to_i
            @persistence.zadd("#{event.id}:unscheduled_maintenances", duration, um_start)
          end

        else
          result = false
        end

        @log.debug("Filter: Ok: #{result ? "block" : "pass"}")
        result
      end
    end
  end
end
