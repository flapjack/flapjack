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

      # NB: should probably be called in the context of a Redis multi block; not doing so
      # here as calling classes may well be adding/updating multiple records in the one
      # operation
      def self.add(entity, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        raise "Entity name not provided" unless entity['name'] && !entity['name'].empty?

        if entity['id']
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
        else
          # empty string is the redis equivalent of a Ruby nil, i.e. key with
          # no value
          redis.set("entity_id:#{entity['name']}", '')
        end
      end

      def self.find_by_name(ent_name, options = {})
        raise "Redis connection not set" unless redis = options[:redis]

        ret = nil
        if defined?(Flapjack::MATCH_ENTITY_PQDN) && Flapjack::MATCH_ENTITY_PQDN
          # will definitely not create if not found
          ret = self.find_or_maybe_create_by_name(ent_name.gsub(/^([^\.]+)\..+$/, '\1'),
                  options.merge(:create => false))
        end

        if ret.nil?
          # will create if not found, if the passed options indicate so
          ret = self.find_or_maybe_create_by_name(ent_name, options)
        end

        ret
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
        @id = options[:id]
        @logger = options[:logger]
      end

      def self.find_or_maybe_create_by_name(ent_name, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        entity_id = redis.get("entity_id:#{ent_name}")
        if entity_id.nil?
          # key doesn't exist
          return unless options[:create]
          self.add({'name' => ent_name}, :redis => redis)
        end
        self.new(:name => ent_name,
                 :id => (entity_id.nil? || entity_id.empty?) ? nil : entity_id,
                 :redis => redis)
      end

    end

  end

end
