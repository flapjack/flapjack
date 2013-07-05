#!/usr/bin/env ruby

require 'flapjack/filters/base'

module Flapjack
  module Filters

    # * If the service event’s state is ok and the previous state was ok, don’t alert
    # * If the service event's state is ok and the previous notification was a recovery, don't alert
    # * If the service event's state is ok and the previous state was not ok and for less than 30
    # seconds, don't alert
    # * If the service event's state is ok and there is unscheduled downtime set, end the unscheduled
    #   downtime
    class Ok
      include Base

      def block?(event)
        result = false

        if event.ok?
          if event.previous_state == 'ok'
            @logger.debug("Filter: Ok: existing state was ok, and the previous state was ok, so blocking")
            result = true
          end

          entity_check = Flapjack::Data::EntityCheck.for_event_id(event.id, :redis => @redis)

          last_notification = entity_check.last_notification
          @logger.debug("Filter: Ok: last notification: #{last_notification.inspect}")
          if last_notification[:type] == 'recovery'
            @logger.debug("Filter: Ok: last notification was a recovery, so blocking")
            result = true
          end

          if event.previous_state != 'ok'
            if event.previous_state_duration < 30
              @logger.debug("Filter: Ok: previous non ok state was for less than 30 seconds, so blocking")
              result = true
            end
          end

          # end any unscheduled downtime
          entity_check.end_unscheduled_maintenance(Time.now.to_i)
        end

        @logger.debug("Filter: Ok: #{result ? "block" : "pass"}")
        result
      end
    end
  end
end
