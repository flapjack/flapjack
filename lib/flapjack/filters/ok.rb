module Flapjack
  module Filters
    class Ok
      def initialize(opts={})
        @log = opts[:log]
      end

      def block?(result)
        !result.warning? || !result.critical?
      end
    end
  end
end
