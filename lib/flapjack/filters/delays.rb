#!/usr/bin/env ruby

require 'flapjack/filters/base'

module Flapjack
  module Filters

    # * If the service event’s state is a failure, and the time since the ok => failure state change
    #   is below a threshold (e.g. 30 seconds), then don't alert
    # * If the service event’s state is a failure, and the time since the last alert is below a
    #   threshold (5 minutes), then don’t alert
    class Delays
      include Base

      # FIXME: the following convenience methods should be put into a class
      # for checks I think, so you can do:
      #   check = Check.new(event.id)
      #   check.state => current state
      #   check.failure? => true if in a failure state (warning or critical)
      #   check.duration_of_current_failure => seconds
      #   check.time_since_last_alert_about_current_problem => seconds
      #   etc ... or something ...
      #   perhaps hang problems off of checks so they are accessable separately

      def check_state(event)
        @persistence.hget(event.id, 'state')
      end

      def check_failed?(event)
        check_state(event) == 'warning' or check_state(event) == 'critical'
      end

      def duration_of_current_failure(event)
        duration    = nil
        if (check_failed?(event))
          duration = Time.now.to_i - @persistence.hget(event.id, 'last_change').to_i
        end
        duration
      end

      def time_since_last_problem_alert(event)
        result = Time.now.to_i - @persistence.get("#{event.id}:last_problem_notification").to_i
        @log.debug("Filter: Delays: time_since_last_problem_alert is returning #{result}")
        result
      end

      def time_since_last_alert_about_current_problem(event)
        duration = nil
        if check_failed?(event)
          time_since_last_problem_alert = time_since_last_problem_alert(event)
          duration_of_current_failure   = duration_of_current_failure(event)
          if (time_since_last_problem_alert < duration_of_current_failure)
            result = time_since_last_problem_alert
            @log.debug("Filter: Delays: time_since_last_alert_about_current_problem is returning #{result}")
            return result
          end
        end
        duration
      end

      def block?(event)
        failure_delay = 30
        resend_delay  = 300

        result = false

        if (event.type == 'service') and (event.critical? or event.warning?)
          time_since_last_alert = -1
          if check_failed?(event)
            if (duration_of_current_failure(event) < failure_delay)
              result = true
              d = duration_of_current_failure(event)
              @log.debug("Filter: Delays: blocking because duration of current failure (#{d}) is less than failure_delay (#{failure_delay})")
            elsif time_since_last_alert_about_current_problem(event) and (time_since_last_alert_about_current_problem(event) < resend_delay)
              result = true
              t = time_since_last_alert_about_current_problem(event)
              @log.debug("Filter: Delays: blocking because time since last alert for current problem (#{t}) is less than resend_delay (#{resend_delay})")
            end
          end
        end

        @log.debug("Filter: Delays: #{result ? "block" : "pass"}")
        result
      end
    end
  end
end
