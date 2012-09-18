#!/usr/bin/env ruby

require 'flapjack/filters/base'

module Flapjack
  module Filters
    # * If the action event’s state is an acknowledgement, and the corresponding check is in a
    #   failure state, then set unscheduled maintenance for 4 hours on the check
    # * If the action event’s state is an acknowledgement, and the corresponding check is not in a
    #   failure state, then don’t alert
    class Acknowledgement
      include Base

      def block?(event)
        timestamp = Time.now.to_i
        result = false
        if event.type == 'action'
          if event.acknowledgement? and @persistence.zscore("failed_checks", event.id)
            ec = Flapjack::Data::EntityCheck.for_event_id(event.id, :redis => @persistence)
            if ec.nil?
              @log.error "Filter: Acknowledgement: unknown entity for event '#{event.id}'"
            else
              ec.create_unscheduled_maintenance(:start_time => timestamp,
                :duration => (event.duration || (4 * 60 * 60)))
              message = "unscheduled maintenance created for #{event.id}"
            end
          else
            message = "no action taken"
            result  = true
            @log.debug("Filter: Acknowledgement: blocking because event.acknowledgement? is false") unless event.acknowledgement?
            @log.debug("Filter: Acknowledgement: blocking because zscore of failed_checks for #{event.id} is false") unless @persistence.zscore("failed_checks", event.id)
          end
        end
        @log.debug("Filter: Acknowledgement: #{result ? "block" : "pass"} (#{message})")
        result
      end
    end
  end
end
