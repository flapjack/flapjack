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

          time_since_last_alert = -1
          if entity_check.failed?
            docf = entity_check.duration_of_current_failure
            tslaacp = entity_check.time_since_last_alert_about_current_problem
            if (docf < failure_delay)
              result = true
              @log.debug("Filter: Delays: blocking because duration of current failure (#{docf}) is less than failure_delay (#{failure_delay})")
            elsif tslaacp and (tslaacp < resend_delay)
              result = true
              @log.debug("Filter: Delays: blocking because time since last alert for current problem (#{tslaacp}) is less than resend_delay (#{resend_delay})")
            end
          end
        end

        @log.debug("Filter: Delays: #{result ? "block" : "pass"}")
        result
      end
    end
  end
end
