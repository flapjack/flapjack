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

      def block?(check, opts = {})
        old_state = opts[:old_state]
        new_state = opts[:new_state]
        timestamp = opts[:timestamp]

        previous_state = opts[:previous_state]

        unless new_state.action.nil? && Flapjack::Data::Condition.healthy?(new_state.condition)
          @logger.debug("Filter: Ok: pass")
          return false
        end

        Flapjack::Data::Check.lock(Flapjack::Data::State, Flapjack::Data::Medium) do
          check.most_severe_notification = nil
          check.clear_unscheduled_maintenance(timestamp)
          unless check.alerting_media.empty?
            @logger.debug("Filter: Ok: clearing alerting media for #{check.id}")
            check.alerting_media.delete(*check.alerting_media.all)
          end
        end

        if old_state.nil? || Flapjack::Data::Condition.healthy?(old_state.condition)
          @logger.debug("Filter: Ok: block - previous state was ok, so blocking")
          @logger.debug(old_state.inspect)
          @logger.debug(new_state.inspect)
          return true
        end

        last_notification = check.states.intersect(:notified => true).last
        @logger.debug("Filter: Ok: last notification: #{last_notification.inspect}")

        if last_notification.nil?
          @logger.debug("Filter: Ok: block - last notification is nil (never notified)")
          return true
        end

        if Flapjack::Data::Condition.healthy?(last_notification.condition)
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
