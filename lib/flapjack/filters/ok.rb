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
            @logger.debug("Filter: Ok: block - previous state was ok, so blocking")
            return true
          end

          entity_check = Flapjack::Data::EntityCheck.for_event_id(event.id, :redis => @redis)

          last_notification = entity_check.last_notification
          @logger.debug("Filter: Ok: last notification: #{last_notification.inspect}")

          unless last_notification[:type]
            @logger.debug("Filter: Ok: block - last notification type is nil (never notified)")
            return true
          end

          if [:recovery, :ok].include?(last_notification[:type])
            @logger.debug("Filter: Ok: block - last notification was a recovery")
            return true
          end

          @logger.debug("Filter: Ok: previous_state: #{event.previous_state}, " +
                        "previous_state_duration: #{event.previous_state_duration}")

          # FIXME: change to if last notification was ok ?
          #unless [:warning, :critical, :unknown, :problem, :acknowledgement].include?(last_notification[:type])
          #  @logger.debug("Filter: Ok: block - last notification was not for a problem or acknowledgement")
          #  return true
          #end

          #if event.previous_state != 'ok'
          #  if event.previous_state_duration < 30
          #    @logger.debug("Filter: Ok: previous non ok state was for less than 30 seconds, so blocking")
          #    result = true
          #  end
          #end

          # end any unscheduled downtime
          entity_check.end_unscheduled_maintenance(Time.now.to_i)
        end

        @logger.debug("Filter: Ok: #{result ? "block" : "pass"}")
        result
      end
    end
  end
end
