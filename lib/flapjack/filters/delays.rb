#!/usr/bin/env ruby

require 'flapjack/data/entity_check'
require 'flapjack/filters/base'

module Flapjack
  module Filters

    # * If the service event’s state is a failure, and the time since the ok => failure state change
    #   is below a threshold (e.g. 30 seconds), then don't alert
    # * If the service event’s state is a failure, and the time since the last alert is below a
    #   threshold (5 minutes), then don’t alert
    class Delays
      include Base

      def block?(event)
        failure_delay = 30
        resend_delay  = 300

        result = false

        if (event.type == 'service') and (event.critical? or event.warning?)

          entity_check = Flapjack::Data::EntityCheck.for_event_id(event.id, :redis => @persistence)
          t = Time.now.to_i

          if entity_check.failed?
            # I think this encapsulates previous logic
            last_problem = entity_check.last_problem_notification
            last_change = entity_check.last_change

            current_failure_duration = t - last_change
            time_since_last_alert = t - last_problem

            if (current_failure_duration < failure_delay)
              result = true
              @log.debug("Filter: Delays: blocking because duration of current failure (#{current_failure_duration}) is less than failure_delay (#{failure_delay})")
            elsif (time_since_last_alert > current_failure_duration) && (time_since_last_alert < resend_delay)
              result = true
              @log.debug("Filter: Delays: blocking because time since last alert for current problem (#{time_since_last_alert}) is less than resend_delay (#{resend_delay})")
            end
          end
        end

        @log.debug("Filter: Delays: #{result ? "block" : "pass"}")
        result
      end
    end
  end
end
