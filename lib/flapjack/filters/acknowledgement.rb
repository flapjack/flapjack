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
          if event.acknowledgement?
            if @redis.zscore("failed_checks", event.id)
              ec = Flapjack::Data::EntityCheck.for_event_id(event.id, :redis => @redis)
              if ec.nil?
                @logger.error "Filter: Acknowledgement: unknown entity for event '#{event.id}'"
              else
                ec.create_unscheduled_maintenance(timestamp,
                  (event.duration || (4 * 60 * 60)),
                  :summary  => event.summary)
                message = "unscheduled maintenance created for #{event.id}"
              end
            else
              result = true
              @logger.debug("Filter: Acknowledgement: blocking because zscore of failed_checks for #{event.id} is false") unless @redis.zscore("failed_checks", event.id)
            end
          else
            message = "no action taken"
            result  = false
          end
        end
        @logger.debug("Filter: Acknowledgement: #{result ? "block" : "pass"} (#{message})")
        result
      end
    end
  end
end
