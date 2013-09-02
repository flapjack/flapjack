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

      def block?(event, entity_check, previous_state)
        failure_delay = 30
        resend_delay  = 300

        label = 'Filter: Delays:'

        unless event.service? && event.failure?
          @logger.debug("#{label} pass - not a service event in a failure state")
          return false
        end

        unless entity_check.failed?
          @logger.debug("#{label} entity_check.failed? returned false ...")
          return false
        end

        last_problem_alert   = entity_check.last_notification_for_state(:problem)[:timestamp]
        last_warning_alert   = entity_check.last_notification_for_state(:warning)[:timestamp]
        last_critical_alert  = entity_check.last_notification_for_state(:critical)[:timestamp]
        last_change          = entity_check.last_change
        last_notification    = entity_check.last_notification
        last_alert_state     = last_notification[:type]
        last_alert_timestamp = last_notification[:timestamp]

        current_time = Time.now.to_i
        current_state_duration = current_time - last_change
        time_since_last_alert  = current_time - last_problem_alert unless last_problem_alert.nil?

        @logger.debug("#{label} last_problem_alert: #{last_problem_alert.to_s}, " +
                      "last_change: #{last_change.inspect}, " +
                      "current_state_duration: #{current_state_duration.inspect}, " +
                      "time_since_last_alert: #{time_since_last_alert.inspect}, " +
                      "last_alert_state: [#{last_alert_state.inspect}], " +
                      "event.state: [#{event.state.inspect}], " +
                      "last_alert_state == event.state ? #{last_alert_state.to_s == event.state}")

        if current_state_duration < failure_delay
          @logger.debug("#{label} block - duration of current failure " +
                     "(#{current_state_duration}) is less than failure_delay (#{failure_delay})")
          return true
        end

        if !last_problem_alert.nil? && (time_since_last_alert < resend_delay) &&
          (last_alert_state.to_s == event.state)

          @logger.debug("#{label} block - time since last alert for " +
                        "current problem (#{time_since_last_alert}) is less than " +
                        "resend_delay (#{resend_delay}) and last alert state (#{last_alert_state}) " +
                        "is equal to current event state (#{event.state})")
          return true
        end

        @logger.debug("#{label} pass - not blocking because neither of the time comparison " +
                      "conditions were met")
        return false

      end
    end
  end
end
