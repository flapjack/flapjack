module Flapjack
  module Filters
    module Base
      def initialize(opts={})
        @log         = opts[:log]
        @persistence = opts[:persistence]
      end

      def name
        self.class.to_s.split('::').last
      end
    end
  end
end
