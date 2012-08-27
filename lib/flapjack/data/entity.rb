#!/usr/bin/env ruby

module Flapjack

  module Data

    class Entity

      attr_accessor :name, :id

      def self.all(options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        redis.keys("entity_id:*").collect {|k|
          k =~ /^entity_id:(.+)$/; entity_name = $1
          self.new(:name => entity_name, :id => redis.get("entity_id:#{entity_name}"), :redis => redis)
        }
      end

      def self.add(entity, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        redis.multi
        existing_name = redis.hget("entity:#{entity['id']}", 'name')
        redis.del("entity_id:#{existing_name}") unless existing_name == entity['name']
        redis.set("entity_id:#{entity['name']}", entity['id'])
        redis.hset("entity:#{entity['id']}", 'name', entity['name'])

        redis.del("contacts_for:#{entity['id']}")
        if entity['contacts'] && entity['contacts'].respond_to?(:each)
          entity['contacts'].each {|contact|
            redis.sadd("contacts_for:#{entity['id']}", contact)
          }
        end
        redis.exec
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
