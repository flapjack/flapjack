#!/usr/bin/env ruby

require 'flapjack/data/contact'
require 'flapjack/data/tag'
require 'flapjack/data/tag_set'

module Flapjack

  module Data

    class Entity

      attr_accessor :name, :id

      TAG_PREFIX = 'entity_tag'

      def self.all(options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        keys = redis.keys("entity_id:*")
        return [] unless keys.any?
        ids = redis.mget(keys)
        keys.collect {|k|
          k =~ /^entity_id:(.+)$/; entity_name = $1
          self.new(:name => entity_name, :id => ids.shift, :redis => redis)
        }.sort_by(&:name)
      end

      # NB: should probably be called in the context of a Redis multi block; not doing so
      # here as calling classes may well be adding/updating multiple records in the one
      # operation
      def self.add(entity, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        raise "Entity name not provided" unless entity['name'] && !entity['name'].empty?

        #FIXME: should probably raise an exception if trying to create a new entity with the
        # same name or id as an existing entity. (Go away and use update instead.)
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

      def self.find_by_ids(entity_ids, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        logger = options[:logger]

        entity_ids.map do |id|
          self.find_by_id(id, options)
        end
      end

      # NB: if we're worried about user input, https://github.com/mudge/re2
      # has bindings for a non-backtracking RE engine that runs in linear
      # time
      def self.find_all_name_matching(pattern, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        begin
          regex = /#{pattern}/
        rescue => e
          if @logger
            @logger.info("Jabber#self.find_all_name_matching - unable to use /#{pattern}/ as a regex pattern: #{e}")
          end
          return nil
        end
        redis.keys('entity_id:*').inject([]) {|memo, check|
          a, entity_name = check.split(':', 2)
          if (entity_name =~ regex) && !memo.include?(entity_name)
            memo << entity_name
          end
          memo
        }.sort
      end

      def self.find_all_with_tags(tags, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        tags_prefixed = tags.collect {|tag|
          "#{TAG_PREFIX}:#{tag}"
        }
        logger.debug "tags_prefixed: #{tags_prefixed.inspect}" if logger = options[:logger]
        Flapjack::Data::Tag.find_intersection(tags_prefixed, :redis => redis).collect {|entity_id|
          Flapjack::Data::Entity.find_by_id(entity_id, :redis => redis).name
        }.compact
      end

      def self.find_all_with_checks(options)
        raise "Redis connection not set" unless redis = options[:redis]
        redis.zrange("current_entities", 0, -1)
      end

      def self.find_all_with_failing_checks(options)
        raise "Redis connection not set" unless redis = options[:redis]
        Flapjack::Data::EntityCheck.find_all_failing_by_entity(:redis => redis).keys
      end

      def self.find_all_current(options)
        raise "Redis connection not set" unless redis = options[:redis]
        redis.zrange('current_entities', 0, -1)
      end

      def self.find_all_current_with_last_update(options)
        raise "Redis connection not set" unless redis = options[:redis]
        redis.zrange('current_entities', 0, -1, {:withscores => true})
      end

      def contacts
        contact_ids = @redis.smembers("contacts_for:#{id}") +
          @redis.smembers("contacts_for:ALL")

        if @logger
          @logger.debug("#{contact_ids.length} contact(s) for #{id} (#{name}): " +
            contact_ids.length)
        end

        contact_ids.collect {|c_id|
          Flapjack::Data::Contact.find_by_id(c_id, :redis => @redis)
        }.compact
      end

      def self.contact_ids_for(entity_ids, options = {})
        raise "Redis connection not set" unless redis = options[:redis]

        entity_ids.inject({}) do |memo, entity_id|
          memo[entity_id] = redis.smembers("contacts_for:#{entity_id}")
          memo
        end
      end

      def check_list
        @redis.zrange("current_checks:#{@name}", 0, -1)
      end

      def check_count
        checks = check_list
        return if checks.nil?
        checks.length
      end

      def tags
        @tags ||= Flapjack::Data::TagSet.new( @redis.keys("#{TAG_PREFIX}:*").inject([]) {|memo, entity_tag|
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

      def as_json(*args)
        {
          "id"    => self.id,
          "name"  => self.name,
        }
      end

      def to_jsonapi(opts = {})
        {
          "id"        => self.id,
          "name"      => self.name,
          "links"     => {
            :contacts   => opts[:contact_ids] || [],
          }
        }.to_json
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
