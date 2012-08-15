module Flapjack
  module Filters
    class Blocker
      def initialize(opts={})
        @log = opts[:log]
      end

      def block?(result)
        true
      end
    end
  end
end
