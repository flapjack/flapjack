#!/usr/bin/env ruby

require 'flapjack/filters/base'

module Flapjack
  module Filters

    # * If there is no previous state for the service event, don't alert
    class NoPreviousState
      include Base

      def block?(event)
        opts = { :redis => @persistence }
        entity_check = Flapjack::Data::EntityCheck.for_event_id(event.id, opts)
        @log.debug("Filter NoPreviousState has created the following entity_check for #{event.id}: #{entity_check.inspect}")

        if entity_check.nil? || entity_check.state.nil?
          @log.debug("Filter: NoPreviousState: previous state not found so blocking")
          result = true
        else
          @log.debug("Filter: NoPreviousState: previous state found so not blocking")
          result = false
        end

        @log.debug("Filter: NoPreviousState: #{result ? "block" : "pass"}")
        result
      end
    end
  end
end
