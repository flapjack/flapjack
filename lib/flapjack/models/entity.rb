#!/usr/bin/env ruby

module Flapjack

  module Data

    class Entity

      def initialize(options = {})
        raise "Redis connection not set" unless @redis = options[:redis]
        raise "Entity not set" unless @entity = options[:entity]
        @logger = options[:logger]
      end

      # FIXME This returns too much irrelevant data -- we'll refactor the data model instead
      def check_list
        @redis.keys("#{@entity}:*").sort
      end

      def check_count
        checks = check_list
        checks.nil? ? nil : checks.length
      end

    end

  end

end
