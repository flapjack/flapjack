#!/usr/bin/env ruby

module Flapjack

  module Data

    class Entity

      def initialize(options = {})
        raise "Redis connection not set" unless @redis = options[:redis]
        raise "Entity not set" unless @entity = options[:entity]
        @logger = options[:logger]
      end

      # NB: this will change when the data model is changed to add check: before them
      def check_list
        @redis.keys("#{@entity}:*").map {|k| k =~ /^#{@entity}:(.+)$/; $1}.reject {|e| e =~ /:/ }
      end

      def check_count
        checks = check_list
        checks.nil? ? nil : checks.length
      end

    end

  end

end
