#!/usr/bin/env ruby

require 'flapjack/data/entity_check'
require 'flapjack/filters/base'

module Flapjack
  module Filters

    # * If the service event’s state is a failure, and the time since the last state change
    #   is below a threshold (e.g. 30 seconds), then don't alert
    # * If the service event’s state is a failure, and the time since the last alert is below a
    #   threshold (5 minutes), and the last notification state is the same as the current state, then don’t alert
    #
    # OLD:
    # * If the service event’s state is a failure, and the time since the ok => failure state change
    #   is below a threshold (e.g. 30 seconds), then don't alert
    # * If the service event’s state is a failure, and the time since the last alert is below a
    #   threshold (5 minutes), and the last notification was not a recovery, then don’t alert
    class Delays
      include Base

      def block?(event)
        failure_delay = 30
        resend_delay  = 300

        result = false

        if event.service? && event.failure?

          entity_check = Flapjack::Data::EntityCheck.for_event_id(event.id, :redis => @redis)
          current_time = Time.now.to_i

          if entity_check.failed?
            last_problem_alert   = entity_check.last_notification_for_state(:problem)
            last_warning_alert   = entity_check.last_notification_for_state(:warning)
            last_critical_alert  = entity_check.last_notification_for_state(:critical)
            last_change          = entity_check.last_change
            last_notification    = entity_check.last_notification
            last_alert_state     = last_notification[:type]
            last_alert_timestamp = last_notification[:timestamp]

            current_state_duration   = current_time - last_change
            time_since_last_alert    = current_time - last_problem_alert unless last_problem_alert.nil?
            @logger.debug("Filter: Delays: last_problem_alert: #{last_problem_alert.to_s}, " +
                       "last_change: #{last_change.inspect}, " +
                       "current_state_duration: #{current_state_duration.inspect}, " +
                       "time_since_last_alert: #{time_since_last_alert.inspect}, " +
                       "last_alert_state: [#{last_alert_state.inspect}], " +
                       "event.state: [#{event.state.inspect}], " +
                       "last_alert_state == event.state ? #{last_alert_state.to_s == event.state}")
            if (current_state_duration < failure_delay)
              result = true
              @logger.debug("Filter: Delays: blocking because duration of current failure " +
                         "(#{current_state_duration}) is less than failure_delay (#{failure_delay})")
            elsif !last_problem_alert.nil? && (time_since_last_alert < resend_delay) &&
              (last_alert_state.to_s == event.state)

              result = true
              @logger.debug("Filter: Delays: blocking because time since last alert for " +
                         "current problem (#{time_since_last_alert}) is less than " +
                         "resend_delay (#{resend_delay}) and last alert state (#{last_alert_state}) " +
                         "is equal to current event state (#{event.state})")
            else
              @logger.debug("Filter: Delays: not blocking because neither of the time comparison " +
                         "conditions were met")
            end
          else
            @logger.debug("Filter: Delays: entity_check.failed? returned false ...")
          end
        end

        @logger.debug("Filter: Delays: #{result ? "block" : "pass"}")
        result
      end
    end
  end
end
