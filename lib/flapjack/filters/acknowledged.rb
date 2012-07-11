#!/usr/bin/env ruby

require 'flapjack/filters/base'

module Flapjack
  module Filters
    class Acknowledged
      include Base

      def block?(event)
        result = @persistence.hget('acknowledged', event.id)
        @log.debug("Filter: Acknowledged: #{result ? "block" : "pass"}")
        result
      end
    end
  end
end
