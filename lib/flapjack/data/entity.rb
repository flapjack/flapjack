#!/usr/bin/env ruby

require 'securerandom'

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

      def self.rename(entity_id, existing_name, entity_name, options = {})
        raise "Redis connection not set" unless redis = options[:redis]

        if redis.renamenx("entity_id:#{existing_name}", "entity_id:#{entity_name}")

          # no way to lock all data operations, so hit & hope... at least the renames
          # should be atomic

          check_state_keys = redis.keys("check:#{existing_name}:*")

          check_history_keys = redis.keys("#{existing_name}:*:states") +
            redis.keys("#{existing_name}:*:state") +
            redis.keys("#{existing_name}:*:summary") +
            redis.keys("#{existing_name}:*:sorted_state_timestamps")

          action_keys = redis.keys("#{existing_name}:*:actions")

          maint_keys = redis.keys("#{existing_name}:*:*scheduled_maintenance*") +

          notif_keys = redis.keys("#{existing_name}:*:last_*_notification") +
            redis.keys("#{existing_name}:*:*_notifications")

          alerting_check_keys = redis.keys("contact_alerting_checks:*")

          failed_checks    = {}
          hashes_to_remove = []
          hashes_to_add    = {}

          alerting_to_remove = {}
          alerting_to_add    = {}

          sha1 = Digest::SHA1.new

          checks = check_state_keys.collect do |state_key|
            state_key =~ /^check:#{Regexp.escape(existing_name)}:(.+)$/
            $1
          end

          checks.each do |ch|
            existing_check = "#{existing_name}:#{ch}"
            new_check      = "#{entity_name}:#{ch}"

            ch_fail_score = redis.zscore("failed_checks", existing_check)
            failed_checks[ch] = ch_fail_score unless ch_fail_score.nil?

            hashes_to_remove << Digest.hexencode(sha1.digest(existing_check))[0..7].downcase
            hashes_to_add[Digest.hexencode(sha1.digest(new_check))[0..7].downcase] = new_check

            alerting_check_keys.each do |ack|
              ack_score = redis.zscore(ack, existing_check)
              unless ack_score.nil?
                alerting_to_remove[ack] ||= []
                alerting_to_remove[ack] << existing_check

                alerting_to_add[ack]    ||= {}
                alerting_to_add[ack][new_check] = ack_score
              end
            end
          end

          current_score = redis.zscore('current_entities', existing_name)

          block_keys = redis.keys("drop_alerts_for_contact:*:*:#{existing_name}:*:*")

          redis.multi

          redis.hset("entity:#{entity_id}", 'name', entity_name)

          check_state_keys.each do |csk|
            redis.rename(csk, csk.sub(/^check:#{Regexp.escape(existing_name)}:/, "check:#{entity_name}:"))
          end

          (check_history_keys + action_keys + maint_keys + notif_keys).each do |chk|
            redis.rename(chk, chk.sub(/^#{Regexp.escape(existing_name)}:/, "#{entity_name}:"))
          end

          # currently failing checks
          failed_checks.each_pair do |ch, score|
            redis.zrem('failed_checks', "#{existing_name}:#{ch}")
            redis.zadd('failed_checks', score, "#{entity_name}:#{ch}")
          end

          redis.rename("current_checks:#{existing_name}", "current_checks:#{entity_name}")

          unless current_score.nil?
            redis.zrem('current_entities', existing_name)
            redis.zadd('current_entities', current_score, entity_name)
          end

          block_keys.each do |blk|
            redis.rename(blk, blk.sub(/^drop_alerts_for_contact:(.+):([^:]+):#{Regexp.escape(existing_name)}:(.+):([^:]+)$/,
              "drop_alerts_for_contact:\\1:\\2:#{entity_name}:\\3:\\4"))
          end

          hashes_to_remove.each   {|hash|      redis.hdel('checks_by_hash', hash) }
          hashes_to_add.each_pair {|hash, chk| redis.hset('checks_by_hash', hash, chk)}

          alerting_to_remove.each_pair do |alerting, chks|
            chks.each {|chk| redis.zrem(alerting, chk)}
          end

          alerting_to_add.each_pair do |alerting, chks|
            chks.each_pair {|chk, score| redis.zadd(alerting, score, chk)}
          end

          redis.exec
        end
      end

      # NB: should probably be called in the context of a Redis multi block; not doing so
      # here as calling classes may well be adding/updating multiple records in the one
      # operation
      def self.add(entity, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        entity_name = entity['name']
        raise "Entity name not provided" if entity_name.nil? || entity_name.empty?

        entity_id = entity['id'] ? entity['id'] : SecureRandom.uuid
        existing_name = redis.hget("entity:#{entity_id}", 'name')

        if existing_name.nil?
          redis.set("entity_id:#{entity['name']}", entity_id)
          redis.hset("entity:#{entity_id}", 'name', entity_name)
        elsif existing_name != entity_name
          rename(entity_id, existing_name, entity_name, :redis => redis)
        end

        redis.del("contacts_for:#{entity_id}")
        if entity['contacts'] && entity['contacts'].respond_to?(:each)
          entity['contacts'].each {|contact_id|
            next if Flapjack::Data::Contact.find_by_id(contact_id, :redis => redis).nil?
            redis.sadd("contacts_for:#{entity_id}", contact_id)
          }
        end
        self.new(:name  => entity_name,
                 :id    => entity_id,
                 :redis => redis)
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
