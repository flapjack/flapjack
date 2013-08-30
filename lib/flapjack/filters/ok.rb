#!/usr/bin/env ruby

require 'flapjack/filters/base'

module Flapjack
  module Filters

    # * If the service event's state is ok and there is unscheduled maintenance set, end the unscheduled
    #   maintenance
    # * If the service event’s state is ok and the previous state was ok, don’t alert
    # * If the service event’s state is ok and there's never been a notification, don't alert
    # * If the service event's state is ok and the previous notification was a recovery or ok, don't alert
    class Ok
      include Base

      def block?(event)

        if event.ok?
          entity_check = Flapjack::Data::EntityCheck.for_event_id(event.id)

          entity_check.end_unscheduled_maintenance(Time.now.to_i)

          if event.previous_state == 'ok'
            @logger.debug("Filter: Ok: block - previous state was ok, so blocking")
            return true
          end

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

        end

        @logger.debug("Filter: Ok: pass")
        return false
      end
    end
  end
end
