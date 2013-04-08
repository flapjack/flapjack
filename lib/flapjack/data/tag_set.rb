#!/usr/bin/env ruby

require 'set'

module Flapjack
  module Data
    class TagSet < ::Set

      def to_json(*a)
        self.to_a.to_json(*a)
      end

    end
  end
end

