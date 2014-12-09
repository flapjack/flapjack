#!/usr/bin/env ruby

require 'flapjack'

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

      def block?(check, opts = {})
        old_state = opts[:old_state]
        new_state = opts[:new_state]
        timestamp = opts[:timestamp]

        initial_failure_delay = check.initial_failure_delay
        if initial_failure_delay.nil? || (initial_failure_delay < 1)
          initial_failure_delay = opts[:initial_failure_delay]
          if initial_failure_delay.nil? || (initial_failure_delay < 1)
            initial_failure_delay = Flapjack::DEFAULT_INITIAL_FAILURE_DELAY
          end
        end

        repeat_failure_delay = check.repeat_failure_delay
        if repeat_failure_delay.nil? || (repeat_failure_delay < 1)
          repeat_failure_delay = opts[:repeat_failure_delay]
          if repeat_failure_delay.nil? || (repeat_failure_delay < 1)
            repeat_failure_delay = Flapjack::DEFAULT_REPEAT_FAILURE_DELAY
          end
        end

        label = 'Filter: Delays:'

        unless new_state.action.nil? && !Flapjack::Data::Condition.healthy?(new_state.condition)
          @logger.debug {
            "#{label} pass - not a service event in a failure state"
          }
          return false
        end

        last_notif  = check.states.intersect(:notified => true).last
        last_problem = check.states.intersect(:condition => Flapjack::Data::Condition.unhealthy.keys,
          :notified => true).last

        last_change_time   = old_state ? old_state.timestamp : nil

        last_problem_alert = last_problem ? last_problem.timestamp : nil

        alert_type        = Flapjack::Data::Alert.notification_type(new_state.action,
          new_state.condition)
        last_alert_type   = last_notif.nil? ? nil :
          Flapjack::Data::Alert.notification_type(last_notif.action, last_notif.condition)

        current_condition_duration = last_change_time.nil? ? nil : (timestamp - last_change_time)
        time_since_last_alert = last_problem_alert.nil? ? nil : (timestamp - last_problem_alert)

        @logger.debug("#{label} last_problem_alert: #{last_problem_alert || 'nil'}, " +
                      "last_change: #{last_change_time || 'nil'}, " +
                      "current_condition_duration: #{current_condition_duration || 'nil'}, " +
                      "time_since_last_alert: #{time_since_last_alert || 'nil'}, " +
                      "alert type: [#{alert_type}], " +
                      "last_alert_type == alert_type ? #{last_alert_type == alert_type}")

        if !current_condition_duration.nil? && (current_condition_duration < initial_failure_delay)
          @logger.debug("#{label} block - duration of current failure " +
                     "(#{current_condition_duration}) is less than failure_delay (#{initial_failure_delay})")
          return true
        end

        if !(last_problem_alert.nil? || time_since_last_alert.nil?) &&
          (time_since_last_alert <= repeat_failure_delay) &&
          (last_alert_type == alert_type)

          @logger.debug("#{label} block - time since last alert for " +
                        "current problem (#{time_since_last_alert}) is less than " +
                        "repeat_failure_delay (#{repeat_failure_delay}) and last alert type (#{last_alert_type}) " +
                        "is equal to current alert type (#{alert_type})")
          return true
        end

        @logger.debug("#{label} pass - not blocking because neither of the time comparison " +
                      "conditions were met")
        return false

      end
    end
  end
end
