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
        result = false

        if event.ok?
          opts = { :redis => @persistence }
          entity_check = Flapjack::Data::EntityCheck.for_event_id(event.id, opts)

          if entity_check
            if entity_check.ok?
              @log.debug("Filter: Ok: existing state was ok, and the previous state was ok, so blocking")
              result = true
            end

            # end any unscheduled downtime
            entity_check.end_unscheduled_maintenance
          end

        end

        @log.debug("Filter: Ok: #{result ? "block" : "pass"}")
        result
      end
    end
  end
end
