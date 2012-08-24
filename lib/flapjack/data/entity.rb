#!/usr/bin/env ruby

module Flapjack

  module Data

    class Entity

      # TODO initialize entity by 'id' from stored data model

      def initialize(options = {})
        raise "Redis connection not set" unless @redis = options[:redis]
        raise "Entity not set" unless @entity = options[:entity]
        @logger = options[:logger]
      end

      def check_list
        @redis.keys("check:#{@entity}:*").map {|k| k =~ /^check:#{@entity}:(.+)$/; $1}
      end

      def check_count
        checks = check_list
        checks.nil? ? nil : checks.length
      end

    end

  end

end
