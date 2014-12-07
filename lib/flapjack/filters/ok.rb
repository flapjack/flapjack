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

      def block?(event, check, opts = {})
        old_state = opts[:old_state]
        new_state = opts[:new_state]
        timestamp = opts[:timestamp]

        previous_state = opts[:previous_state]

        healthy = Flapjack::Data::Condition::HEALTHY.values

        unless healthy.include?(new_state.condition)
          @logger.debug("Filter: Ok: pass")
          return false
        end

        check.clear_unscheduled_maintenance(timestamp)

        unless old_state.nil? || healthy.include?(old_state.condition)
          @logger.debug("Filter: Ok: block - previous state was ok, so blocking")
          return true
        end

        last_notification = check.states.intersect(:notified => true).last
        @logger.debug("Filter: Ok: last notification: #{last_notification.inspect}")

        if last_notification.nil?
          @logger.debug("Filter: Ok: block - last notification is nil (never notified)")
          return true
        end

        if healthy.include?(last_notification.condition)
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
