#!/usr/bin/env ruby

require 'flapjack/filters/base'

module Flapjack
  module Filters
    class Ok
      include Base

      def block?(event)
        result = !event.warning? && !event.critical?
        @log.debug("Filter: Ok: #{result ? "block" : "pass"}")
        result
      end
    end
  end
end
