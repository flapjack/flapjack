
require 'flapjack/filters/base'

module Flapjack
  module Filters
    # If the action event’s state is an acknowledgement, and the corresponding service is in a
    # failure state, then set an acknowledgement flag
    class AcknowledgementOfFailed
      include Base

      def block?(event)
        if event.acknowledgement? and @persistence.zscore("failed_services", event.id)
          # FIXME - put a timestamp in here instead of 'true' perhaps
          @persistence.hset('acknowledged', event.id, 'true')
          message = "acknowledgement created for #{event.id}"
        else
          message = "no action taken"
        end
        result = false
        @log.debug("Filter: AcknowledgementOfFailed: #{result ? "block" : "pass"} (#{message})")
        result
      end
    end
  end
end
