module Flapjack
  module Filters
    class AnyParentsFailed
      def initialize(opts={})
        @log = opts[:log]
        @persistence = opts[:persistence]
      end

      def block?(result)
        @persistence.any_parents_failed?(result)
      end
    end
  end
end
