module Flapjack
  module Filters
    class Mock
      def initialize(opts={})
        @log = opts[:log]
      end

      def block?(result)
        false
      end
    end
  end
end
