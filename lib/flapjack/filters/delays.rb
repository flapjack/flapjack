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

        initial_failure_delay = opts[:initial_failure_delay]
        repeat_failure_delay = opts[:repeat_failure_delay]

        initial_recovery_delay = opts[:initial_recovery_delay]

        label = 'Filter: Delays:'

        if new_state.nil? || !new_state.action.nil?
          Flapjack.logger.debug {
            "#{label} pass - not a service event in a known state"
          }
          return false
        end

        if (old_state.nil? || Flapjack::Data::Condition.healthy?(old_state.condition)) &&
          !Flapjack::Data::Condition.healthy?(new_state.condition)

          # just failed
          if initial_failure_delay > 0
            Flapjack.logger.debug("#{label} block - just failed, failure_delay = #{initial_failure_delay}")
            return true
          end
        elsif !old_state.nil? && !Flapjack::Data::Condition.healthy?(old_state.condition) &&
          Flapjack::Data::Condition.healthy?(new_state.condition)

          # just recovered
          if initial_recovery_delay > 0
            Flapjack.logger.debug("#{label} block - just recovered, recovery_delay = #{initial_recovery_delay}")
            return true
          end
        else
          last_change_time = old_state.nil? ? nil : old_state.created_at
          current_condition_duration = last_change_time.nil? ? nil : (timestamp - last_change_time)

          if Flapjack::Data::Condition.healthy?(new_state.condition)
            if !current_condition_duration.nil? && (current_condition_duration < initial_recovery_delay)
              Flapjack.logger.debug("#{label} block - duration of current success " +
                         "(#{current_condition_duration}) is less than recovery_delay (#{initial_recovery_delay})")
              return true
            end

            Flapjack.logger.debug("#{label} pass - not blocking due to recovery delay - " \
              "current duration #{current_condition_duration}, initial_recovery_delay #{initial_recovery_delay}")
            false
          else
            if !current_condition_duration.nil? && (current_condition_duration < initial_failure_delay)
              Flapjack.logger.debug("#{label} block - duration of current failure " +
                         "(#{current_condition_duration}) is less than failure_delay (#{initial_failure_delay})")
              return true
            end

            last_problem  = check.latest_notifications.
              intersect(:condition => Flapjack::Data::Condition.unhealthy.keys).first
            last_recovery = check.latest_notifications.
              intersect(:condition => Flapjack::Data::Condition.healthy.keys).first
            last_ack      = check.latest_notifications.
              intersect(:action => 'acknowledgement').first

            last_problem_time  = last_problem.nil?  ? nil : last_problem.created_at
            last_notif = [last_problem, last_recovery, last_ack].compact.
                           sort_by(&:created_at).last

            alert_type = Flapjack::Data::Alert.notification_type(new_state.action,
              new_state.condition)

            last_alert_type = last_notif.nil? ? nil :
              Flapjack::Data::Alert.notification_type(last_notif.action, last_notif.condition)

            time_since_last_alert = last_problem_time.nil? ? nil : (timestamp - last_problem_time)

            Flapjack.logger.debug("#{label} last_problem: #{last_problem_time || 'nil'}, " +
                          "last_change: #{last_change_time || 'nil'}, " +
                          "current_condition_duration: #{current_condition_duration || 'nil'}, " +
                          "time_since_last_alert: #{time_since_last_alert || 'nil'}, " +
                          "alert type: [#{alert_type}], " +
                          "last_alert_type == alert_type ? #{last_alert_type == alert_type}")

            if !(last_problem_time.nil? || time_since_last_alert.nil?) &&
              (time_since_last_alert <= repeat_failure_delay) &&
              (last_alert_type == alert_type)

              Flapjack.logger.debug("#{label} block - time since last alert for " +
                            "current problem (#{time_since_last_alert}) is less than " +
                            "repeat_failure_delay (#{repeat_failure_delay}) and last alert type (#{last_alert_type}) " +
                            "is equal to current alert type (#{alert_type})")
              return true
            end

            Flapjack.logger.debug("#{label} pass - not blocking because neither of the time comparison " +
                          "conditions were met")
            false
          end
        end
      end
    end
  end
end
