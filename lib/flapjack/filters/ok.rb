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
        new_entry = opts[:new_entry]
        timestamp = opts[:timestamp]

        previous_state = opts[:previous_state]

        unless new_entry.action.nil? && Flapjack::Data::Condition.healthy?(new_entry.condition)
          Flapjack.logger.debug("Filter: Ok: pass")
          return false
        end

        Flapjack::Data::Check.lock(Flapjack::Data::State, Flapjack::Data::Medium) do
          check.most_severe = nil
          check.clear_unscheduled_maintenance(timestamp)
          unless check.alerting_media.empty?
            Flapjack.logger.debug("Filter: Ok: clearing alerting media for #{check.id}")
            check.alerting_media.delete(*check.alerting_media.all)
          end
        end

        if old_state.nil? || Flapjack::Data::Condition.healthy?(old_state.condition)
          Flapjack.logger.debug("Filter: Ok: block - previous state was ok, so blocking")
          Flapjack.logger.debug(old_state.inspect)
          Flapjack.logger.debug(new_entry.inspect)
          return true
        end

        last_notification = check.latest_notifications.last
        Flapjack.logger.debug("Filter: Ok: last notification: #{last_notification.inspect}")

        if last_notification.nil?
          Flapjack.logger.debug("Filter: Ok: block - last notification is nil (never notified)")
          return true
        end

        if Flapjack::Data::Condition.healthy?(last_notification.condition)
          Flapjack.logger.debug("Filter: Ok: block - last notification was a recovery")
          return true
        end

        Flapjack.logger.debug("Filter: Ok: previous_state: #{previous_state.inspect}")
        Flapjack.logger.debug("Filter: Ok: pass")
        false
      end
    end
  end
end
