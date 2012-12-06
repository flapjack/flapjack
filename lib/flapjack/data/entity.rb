#!/usr/bin/env ruby

require 'flapjack/data/contact'
require 'flapjack/data/tag'

module Flapjack

  module Data

    class Entity

      attr_accessor :name, :id

      TAG_PREFIX = 'entity_tag'

      def self.all(options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        redis.keys("entity_id:*").collect {|k|
          k =~ /^entity_id:(.+)$/; entity_name = $1
          self.new(:name => entity_name, :id => redis.get("entity_id:#{entity_name}"), :redis => redis)
        }.sort_by(&:name)
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
            entity['contacts'].each {|contact_id|
              next if Flapjack::Data::Contact.find_by_id(contact_id, :redis => redis).nil?
              redis.sadd("contacts_for:#{entity['id']}", contact_id)
            }
          end
          self.new(:name  => entity['name'],
                   :id    => entity['id'],
                   :redis => redis)
        else
          # empty string is the redis equivalent of a Ruby nil, i.e. key with
          # no value
          redis.set("entity_id:#{entity['name']}", '')
          nil
        end
      end

      def self.find_by_name(entity_name, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        entity_id = redis.get("entity_id:#{entity_name}")
        if entity_id.nil?
          # key doesn't exist
          return unless options[:create]
          self.add({'name' => entity_name}, :redis => redis)
        end
        self.new(:name => entity_name,
                 :id => (entity_id.nil? || entity_id.empty?) ? nil : entity_id,
                 :redis => redis)
      end

      def self.find_by_id(entity_id, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        entity_name = redis.hget("entity:#{entity_id}", 'name')
        return if entity_name.nil? || entity_name.empty?
        self.new(:name => entity_name, :id => entity_id, :redis => redis)
      end

      # NB: if we're worried about user input, https://github.com/mudge/re2
      # has bindings for a non-backtracking RE engine that runs in linear
      # time
      def self.find_all_name_matching(pattern, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        redis.keys('entity_id:*').inject([]) {|memo, check|
          a, entity_name = check.split(':')
          if (entity_name =~ /#{pattern}/) && !memo.include?(entity_name)
            memo << entity_name
          end
          memo
        }.sort
      end

      def contacts
        contact_ids = @redis.smembers("contacts_for:#{id}")

        if @logger
          @logger.debug("#{contact_ids.length} contact(s) for #{id} (#{name}): " +
            contact_ids.length)
        end

        contact_ids.collect {|c_id|
          Flapjack::Data::Contact.find_by_id(c_id, :redis => @redis)
        }.compact
      end

      def check_list
        @redis.keys("check:#{@name}:*").map {|k| k =~ /^check:#{@name}:(.+)$/; $1}
      end

      def check_count
        checks = check_list
        return if checks.nil?
        checks.length
      end

      def tags
        @tags ||= ::Set.new( @redis.keys("#{TAG_PREFIX}:*").inject([]) {|memo, entity_tag|
          if Flapjack::Data::Tag.find(entity_tag, :redis => @redis).include?(@id.to_s)
            memo << entity_tag.sub(/^#{TAG_PREFIX}:/, '')
          end
          memo
        } )
      end

      def add_tags(*enum)
        enum.each do |t|
          Flapjack::Data::Tag.create("#{TAG_PREFIX}:#{t}", [@id], :redis => @redis)
          tags.add(t)
        end
      end

      def delete_tags(*enum)
        enum.each do |t|
          tag = Flapjack::Data::Tag.find("#{TAG_PREFIX}:#{t}", :redis => @redis)
          tag.delete(@id)
          tags.delete(t)
        end
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

    end

  end

end
