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

        unless event.service? && Flapjack::Data::CheckStateR.failing_states.include?( event.state )
          @logger.debug("#{label} pass - not a service event in a failure state")
          return false
        end

        unless Flapjack::Data::CheckStateR.failing_states.include?( entity_check.state )
          @logger.debug("#{label} entity_check is not failing...")
          return false
        end

        last_problem  = entity_check.notifications.intersect(:type => 'problem').last
        last_change   = entity_check.states.last
        last_notif    = entity_check.notifications.last

        last_problem_time  = last_problem  ? last_problem.timestamp  : nil
        last_change_time   = last_change   ? last_change.timestamp   : nil
        last_alert_state   = last_notif    ? last_notif.state        : nil

        current_time = Time.now.to_i
        current_state_duration = last_change_time.nil?  ? nil : current_time - last_change_time
        time_since_last_alert  = last_problem_time.nil? ? nil : current_time - last_problem_time

        @logger.debug("#{label} last_problem_alert: #{last_problem_time || 'nil'}, " +
                      "last_change: #{last_change_time || 'nil'}, " +
                      "current_state_duration: #{current_state_duration || 'nil'}, " +
                      "time_since_last_alert: #{time_since_last_alert || 'nil'}, " +
                      "last_alert_state: [#{last_alert_state}], " +
                      "event.state: [#{event.state}], " +
                      "last_alert_state == event.state ? #{last_alert_state == event.state}")

        if current_state_duration < failure_delay
          @logger.debug("#{label} block - duration of current failure " +
                     "(#{current_state_duration}) is less than failure_delay (#{failure_delay})")
          return true
        end

        if !(last_problem_time.nil? || time_since_last_alert.nil?) &&
          (time_since_last_alert < resend_delay) &&
          (last_alert_state == event.state)

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
