#!/usr/bin/env ruby

module Flapjack

  module Data

    class Entity

      def initialize(options = {})
        raise "Redis connection not set" unless @redis = options[:redis]
        raise "Entity not set" unless @entity = options[:entity]
        @logger = options[:logger]
      end

      def check_list
        # This returns too much irrelevant data -- we'll refactor the data model instead
        @redis.keys("#{@entity}:*").sort
      end

    end

  end

end
