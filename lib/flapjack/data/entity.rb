#!/usr/bin/env ruby

require 'flapjack/data/contact'
require 'flapjack/data/tag'
require 'flapjack/data/tag_set'

module Flapjack

  module Data

    class Entity

      attr_accessor :name, :id

      TAG_PREFIX = 'entity_tag'

      def self.all
        Flapjack.redis.keys("entity_id:*").collect {|k|
          k =~ /^entity_id:(.+)$/; entity_name = $1
          self.new(:name => entity_name,
                   :id => Flapjack.redis.get("entity_id:#{entity_name}"))
        }.sort_by(&:name)
      end

      # NB: should probably be called in the context of a Redis multi block; not doing so
      # here as calling classes may well be adding/updating multiple records in the one
      # operation
      def self.add(entity)
        raise "Entity name not provided" unless entity['name'] && !entity['name'].empty?

        if entity['id']
          existing_name = Flapjack.redis.hget("entity:#{entity['id']}", 'name')
          Flapjack.redis.del("entity_id:#{existing_name}") unless existing_name == entity['name']
          Flapjack.redis.set("entity_id:#{entity['name']}", entity['id'])
          Flapjack.redis.hset("entity:#{entity['id']}", 'name', entity['name'])

          Flapjack.redis.del("contacts_for:#{entity['id']}")
          if entity['contacts'] && entity['contacts'].respond_to?(:each)
            entity['contacts'].each {|contact_id|
              next if Flapjack::Data::Contact.find_by_id(contact_id).nil?
              Flapjack.redis.sadd("contacts_for:#{entity['id']}", contact_id)
            }
          end
          self.new(:name  => entity['name'],
                   :id    => entity['id'])
        else
          # empty string is the redis equivalent of a Ruby nil, i.e. key with
          # no value
          Flapjack.redis.set("entity_id:#{entity['name']}", '')
          nil
        end
      end

      def self.find_by_name(entity_name, options = {})
        entity_id = Flapjack.redis.get("entity_id:#{entity_name}")
        if entity_id.nil?
          # key doesn't exist
          return unless options[:create]
          self.add({'name' => entity_name})
        end
        self.new(:name => entity_name,
                 :id => (entity_id.nil? || entity_id.empty?) ? nil : entity_id)
      end

      def self.find_by_id(entity_id)
        entity_name = Flapjack.redis.hget("entity:#{entity_id}", 'name')
        return if entity_name.nil? || entity_name.empty?
        self.new(:name => entity_name, :id => entity_id)
      end

      # NB: if we're worried about user input, https://github.com/mudge/re2
      # has bindings for a non-backtracking RE engine that runs in linear
      # time
      def self.find_all_name_matching(pattern)
        begin
          regex = /#{pattern}/
        rescue => e
          if @logger
            @logger.info("Jabber#self.find_all_name_matching - unable to use /#{pattern}/ as a regex pattern: #{e}")
          end
          return nil
        end
        Flapjack.redis.keys('entity_id:*').inject([]) {|memo, check|
          a, entity_name = check.split(':', 2)
          if (entity_name =~ regex) && !memo.include?(entity_name)
            memo << entity_name
          end
          memo
        }.sort
      end

      def self.find_all_with_tags(tags, options = {})
        tags_prefixed = tags.collect {|tag|
          "#{TAG_PREFIX}:#{tag}"
        }
        logger.debug "tags_prefixed: #{tags_prefixed.inspect}" if logger = options[:logger]
        Flapjack::Data::Tag.find_intersection(tags_prefixed).collect {|entity_id|
          Flapjack::Data::Entity.find_by_id(entity_id).name
        }.compact
      end

      def self.find_all_with_checks
        Flapjack.redis.zrange("current_entities", 0, -1)
      end

      def self.find_all_with_failing_checks
        # TODO seems odd to call into another class for this -- maybe reverse them?
        Flapjack::Data::EntityCheck.find_all_failing_by_entity.keys
      end

      def self.find_all_current
        Flapjack.redis.zrange('current_entities', 0, -1)
      end

      def self.find_all_current_with_last_update
        Flapjack.redis.zrange('current_entities', 0, -1, :withscores => true)
      end

      def contacts
        contact_ids = Flapjack.redis.smembers("contacts_for:#{id}")

        if @logger
          @logger.debug("#{contact_ids.length} contact(s) for #{id} (#{name}): " +
            contact_ids.length)
        end

        contact_ids.collect {|c_id|
          Flapjack::Data::Contact.find_by_id(c_id)
        }.compact
      end

      def check_list
        Flapjack.redis.zrange("current_checks:#{@name}", 0, -1)
      end

      def check_count
        checks = check_list
        return if checks.nil?
        checks.length
      end

      def tags
        @tags ||= Flapjack::Data::TagSet.new( Flapjack.redis.keys("#{TAG_PREFIX}:*").inject([]) {|memo, entity_tag|
          if Flapjack::Data::Tag.find(entity_tag).include?(@id.to_s)
            memo << entity_tag.sub(/^#{TAG_PREFIX}:/, '')
          end
          memo
        } )
      end

      def add_tags(*enum)
        enum.each do |t|
          Flapjack::Data::Tag.create("#{TAG_PREFIX}:#{t}", [@id])
          tags.add(t)
        end
      end

      def delete_tags(*enum)
        enum.each do |t|
          tag = Flapjack::Data::Tag.find("#{TAG_PREFIX}:#{t}")
          tag.delete(@id)
          tags.delete(t)
        end
      end

    private

      # NB: initializer should not be used directly -- instead one of the finder methods
      # above will call it
      def initialize(options = {})
        raise "Entity name not set" unless @name = options[:name]
        @id = options[:id]
        @logger = options[:logger]
      end

    end

  end

end
