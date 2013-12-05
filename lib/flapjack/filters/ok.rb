#!/usr/bin/env ruby

require 'flapjack/data/check_state'

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

      def block?(event, check, previous_state)
        unless Flapjack::Data::CheckState.ok_states.include?( event.state )
          @logger.debug("Filter: Ok: pass")
          return false
        end

        check.clear_unscheduled_maintenance(Time.now)

        if !previous_state.nil? && Flapjack::Data::CheckState.ok_states.include?( previous_state.state )
          @logger.debug("Filter: Ok: block - previous state was ok, so blocking")
          return true
        end

        last_notification = check.last_notification
        @logger.debug("Filter: Ok: last notification: #{last_notification.inspect}")

        if last_notification.nil?
          @logger.debug("Filter: Ok: block - last notification is nil (never notified)")
          return true
        end

        if last_notification.respond_to?(:state) &&
           Flapjack::Data::CheckState.ok_states.include?(last_notification.state)

          @logger.debug("Filter: Ok: block - last notification was a recovery")
          return true
        end

        @logger.debug("Filter: Ok: previous_state: #{previous_state.inspect}")
        @logger.debug("Filter: Ok: pass")
        false
      end
    end
  end
end
