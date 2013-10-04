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

      def block?(event, entity_check, previous_state)
        unless Flapjack::Data::CheckStateR.ok_states.include?( event.state )
          @logger.debug("Filter: Ok: pass")
          return false
        end

        entity_check.clear_unscheduled_maintenance(Time.now.to_i)

        if Flapjack::Data::CheckStateR.ok_states.include?( previous_state )
          @logger.debug("Filter: Ok: block - previous state was ok, so blocking")
          return true
        end

        last_notification = entity_check.states.intersect(:notified => true).last
        @logger.debug("Filter: Ok: last notification: #{last_notification.inspect}")

        if last_notification.nil? || last_notification.state.nil?
          @logger.debug("Filter: Ok: block - last notification type is nil (never notified)")
          return true
        end

        if Flapjack::Data::CheckStateR.ok_states.include?(last_notification.state)
          @logger.debug("Filter: Ok: block - last notification was a recovery")
          return true
        end

        @logger.debug("Filter: Ok: previous_state: #{previous_state}")
        @logger.debug("Filter: Ok: pass")
        false
      end
    end
  end
end
