#!/usr/bin/env ruby

module Flapjack
  module Filters
    module Base
      def name
        self.class.to_s.split('::').last
      end
    end
  end
end
