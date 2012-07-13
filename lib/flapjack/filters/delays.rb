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
      # for services I think, so you can do:
      #   service = Service.new(event.id)
      #   service.state => current state
      #   service.failure? => true if in a failure state (warning or critical)
      #   service.duration_of_current_failure => seconds
      #   service.time_since_last_alert_about_current_problem => seconds
      #   etc ... or something ...
      #   perhaps hang problems off of services so they are accessable separately

      def service_state(event)
        @persistence.hget(event.id, 'state')
      end

      def service_failed?(event)
        service_state(event) == 'warning' or service_state(event) == 'critical'
      end

      def duration_of_current_failure(event)
        duration    = nil
        if (service_failed?(event))
          duration = Time.now.to_i - @persistence.hget(event.id, 'last_change').to_i
        end
        duration
      end

      def time_since_last_problem_alert(event)
        Time.now.to_i - @persistence.get("#{event.id}:last_problem_notification").to_i
      end

      def time_since_last_alert_about_current_problem(event)
        duration = nil
        if service_failed?(event)
          time_since_last_problem_alert = time_since_last_problem_alert(event)
          duration_of_current_failure   = duration_of_current_failure(event)
          if (time_since_last_problem_alert < duration_of_current_failure)
            return time_since_last_problem_alert
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
          if service_failed?(event)
            if (duration_of_current_failure(event) < failure_delay)
              result = true
            elsif time_since_last_alert_about_current_problem(event) and (time_since_last_alert_about_current_problem(event) < resend_delay)
              result = true
            end
          end
        end

        @log.debug("Filter: Delays: #{result ? "block" : "pass"}")
        result
      end
    end
  end
end
