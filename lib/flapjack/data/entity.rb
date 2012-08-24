#!/usr/bin/env ruby

module Flapjack

  module Data

    class Entity

      attr_accessor :name, :id

      # TODO use a global pointer to a synchrony-based connection pool
      def self.initialize_redis
      end

      def self.all(options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        redis.keys("entity_id:*").collect {|k|
          k =~ /^entity_id:(.+)$/; entity_name = $1
          self.new(:name => entity_name, :id => redis.get("entity_id:#{entity_name}"), :redis => redis)
        }
      end

      def self.find_by_name(entity_name, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        entity_id = redis.get("entity_id:#{entity_name}")
        return if entity_id.nil? || (entity_id.to_i == 0)
        self.new(:name => entity_name, :id => entity_id.to_i, :redis => redis)
      end

      def self.find_by_id(entity_id, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        entity_name = redis.hget("entity:#{entity_id}", 'name')
        return if entity_name.nil? || entity_name.empty?
        self.new(:name => entity_name, :id => entity_id, :redis => redis)
      end

      def check_list
        @redis.keys("check:#{@name}:*").map {|k| k =~ /^check:#{@name}:(.+)$/; $1}
      end

      def check_count
        checks = check_list
        return if checks.nil?
        checks.length
      end

    private

      # NB: initializer should not be used directly -- instead one of the finder methods
      # above will call it
      def initialize(options = {})
        raise "Redis connection not set" unless @redis = options[:redis]
        raise "Entity name not set" unless @name = options[:name]
        raise "Entity id not set" unless @id = options[:id]
        @logger = options[:logger]
      end

    end

  end

end
