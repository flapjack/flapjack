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

        current_entity_names = (options.has_key?(:enabled) && !options[:enabled].nil?) ?
          Flapjack::Data::Entity.current_names : nil

        keys = redis.keys("entity_id:*")
        return [] unless keys.any?
        ids = redis.mget(keys)
        keys.inject([]) {|memo, k|
          k =~ /^entity_id:(.+)$/; entity_name = $1; entity_id = ids.shift

          if options[:enabled].nil? ||
            (options[:enabled].is_a?(TrueClass) && current_entity_names.include?(entity_name) ) ||
            (options[:enabled].is_a(FalseClass) && !current_entity_names.include?(entity_name))

            memo << self.new(:name => entity_name, :id => entity_id, :redis => redis)
          end

          memo
        }.sort_by(&:name)
      end

      # no way to lock all data operations, so hit & hope... at least the renames
      # should be atomic
      def self.rename(existing_name, entity_name, options = {})
        raise "Redis connection not set" unless redis = options[:redis]

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

        yield if block_given? # entity id -> name update from add()

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

      # NB only used by the 'entities:reparent' Rake task, but kept in this
      # class to be more easily testable
      def self.merge(old_name, current_name, options = {})
        raise "Redis connection not set" unless redis = options[:redis]

        check_state_keys = redis.keys("check:#{old_name}:*")

        checks = check_state_keys.collect do |state_key|
          state_key =~ /^check:#{Regexp.escape(old_name)}:(.+)$/
          $1
        end

        alerting_check_keys = redis.keys("contact_alerting_checks:*")

        keys_to_delete = []
        keys_to_rename = {}

        failed_checks_to_remove = []
        failed_checks_to_add    = {}

        action_data    = {}

        notification_types = ['problem', 'unknown', 'warning', 'critical',
          'recovery', 'acknowledgement']

        alerting_check_keys = redis.keys("contact_alerting_checks:*")

        alerting_to_remove = {}
        alerting_to_add    = {}

        block_keys = redis.keys("drop_alerts_for_contact:*:*:#{old_name}:*:*")

        checks.each do |ch|
          old_check     = "#{old_name}:#{ch}"
          current_check = "#{current_name}:#{ch}"

          old_states = "#{old_check}:states"
          new_states = "#{current_check}:states"

          failed_checks_to_remove << old_check

          if redis.exists("check:#{current_check}")
            keys_to_delete << "check:#{old_check}"

            loop do
              # pop from tail, append at head, matches ordering in EntityCheck#update_state
              break if redis.rpoplpush(old_states, new_states).nil?
            end

            keys_to_delete << old_states
          else

            # can move a failing checks entry over, if it exists
            ch_fail_score = redis.zscore("failed_checks", old_check)
            failed_checks_to_add[current_check] = ch_fail_score unless ch_fail_score.nil?

            keys_to_rename["check:#{old_check}"] = "check:#{current_check}"
            keys_to_rename[old_states]           = new_states
          end

          notification_types.each do |notif|

            old_notif = "#{old_check}:#{notif}_notifications"
            new_notif = "#{current_check}:#{notif}_notifications"

            if redis.exists(new_notif)
              loop do
                # pop from tail, append at head
                break if redis.rpoplpush(old_notif, new_notif).nil?
              end

              keys_to_delete << old_notif
            else
              keys_to_rename[old_notif] = new_notif
            end
          end

          alerting_check_keys.each do |ack|
            old_score = redis.zscore(ack, old_check)
            new_score = redis.zscore(ack, current_check)

            alerting_to_remove[ack] ||= []
            alerting_to_remove[ack] << old_check

            # nil.to_i == 0, which is good for a missing value
            if !old_score.nil? && new_score.nil? &&
               (redis.lindex("#{old_check}:problem_notifications", -1).to_i >
                [redis.lindex("#{current_check}:recovery_notifications", -1).to_i,
                 redis.lindex("#{current_check}:acknowledgement_notifications", -1).to_i].max)

              alerting_to_add[ack]    ||= {}
              alerting_to_add[ack][current_check] = old_score
            end
          end

        end

        if redis.exists("current_checks:#{current_name}")
          keys_to_delete << "current_checks:#{old_name}"
        else
          keys_to_rename["current_checks:#{old_name}"] = "current_checks:#{current_name}"
        end

        current_score = redis.zscore('current_entities', current_name)
        old_score     = nil

        if current_score.nil?
          old_score = redis.zscore('current_entities', old_name)
        end

        check_timestamps_keys = redis.keys("#{old_name}:*:sorted_state_timestamps")
        keys_to_delete += check_timestamps_keys

        check_history_keys = redis.keys("#{old_name}:*:state") +
          redis.keys("#{old_name}:*:summary")

        action_keys = redis.keys("#{old_name}:*:actions")

        action_keys.each do |old_actions|

          old_actions =~ /^#{Regexp.escape(old_name)}:(.+):actions$/
          current_actions = "#{current_name}:#{$1}:actions"

          if redis.exists(current_actions)
            action_data[current_actions] = redis.hgetall(old_actions)
            keys_to_delete << old_actions
          else
            keys_to_rename[old_actions] = current_actions
          end
        end

        maint_keys = redis.keys("#{old_name}:*:*scheduled_maintenance")

        maints_to_delete = []
        maints_to_set    = {}

        maint_keys.each do |maint_key|
          maint_key =~ /^#{Regexp.escape(old_name)}:(.+):((?:un)?scheduled_maintenance)$/
          maint_check = $1
          maint_type  = $2

          new_maint_key = "#{current_name}:#{maint_check}:#{maint_type}"

          # as keys are expiring, check all steps in case they have
          old_time, new_time = redis.mget(maint_key, new_maint_key).map(&:to_i)

          old_ttl = (old_time <= 0) ? -1 : redis.ttl(maint_key)
          new_ttl = (new_time <= 0) ? -1 : redis.ttl(new_maint_key)

          # TTL < 0 is a redis error code -- key not present, etc.
          if (old_ttl >= 0) && ((new_ttl < 0) ||
               ((old_time + old_ttl) > (new_time + new_ttl)))
            keys_to_rename[maint_key] = new_maint_key
            maints_to_set[new_maint_key] = redis.zscore("#{maint_key}s", old_time)
          end

          keys_to_delete << maint_key
        end

        blocks_to_set = {}

        block_keys.each do |block_key|
          block_key =~ /^drop_alerts_for_contact:(.+):([^:]+):#{Regexp.escape(old_name)}:(.+):([^:]+)$/
          new_block_key = "drop_alerts_for_contact:#{$1}:#{$2}:#{current_name}:#{$3}:#{$4}"

          # as keys may expire, check whether they have
          old_start_ttl, new_start_ttl = redis.mget(block_key, new_block_key).map(&:to_i)

          old_ttl = (old_start_ttl <= 0) ? -1 : redis.ttl(block_key)
          new_ttl = (new_start_ttl <= 0) ? -1 : redis.ttl(new_block_key)

          # TTL < 0 is a redis error code -- key not present, etc.
          if (old_ttl >= 0) && ((new_ttl < 0) || (old_ttl > new_ttl))
            blocks_to_set[new_block_key] = [Time.now.to_i + old_ttl, old_start_ttl]
          end

          keys_to_delete << block_key
        end

        stored_maint_keys = redis.keys("#{old_name}:*:*scheduled_maintenances") +
          redis.keys("#{old_name}:*:sorted_*scheduled_maintenance_timestamps")
        keys_to_delete += stored_maint_keys

        notif_keys = redis.keys("#{old_name}:*:last_*_notification")

        redis.multi

        check_history_keys.each do |chk|
          redis.renamenx(chk, chk.sub(/^#{Regexp.escape(old_name)}:/, "#{current_name}:"))
        end

        check_timestamps_keys.each do |ctk|
          dest = ctk.sub(/^#{Regexp.escape(old_name)}:/, "#{current_name}:")
          redis.zunionstore(dest, [ctk, dest], :aggregate => :max)
        end

        failed_checks_to_remove.each do |fctr|
          redis.zrem('failed_checks', fctr)
        end

        failed_checks_to_add.each_pair do |fcta, score|
          redis.zadd('failed_checks', score, fcta)
        end

        action_data.each_pair do |action_key, data|
          data.each_pair do |k, v|
            redis.hsetnx(action_key, k, v)
          end
        end

        redis.zunionstore("current_checks:#{current_name}",
          ["current_checks:#{old_name}", "current_checks:#{current_name}"],
          :aggregate => :max)

        redis.zrem('current_entities', old_name)
        unless old_score.nil?
          redis.zadd('current_entities', old_score, current_name)
        end

        maints_to_set.each_pair do |maint_key, score|
          redis.zadd("#{maint_key}s", score, current_name)
        end

        stored_maint_keys.each do |stored_maint_key|
          new_stored_maint_key = stored_maint_key.sub(/^#{Regexp.escape(old_name)}:/, "#{current_name}:")
          redis.zunionstore(new_stored_maint_key,
            [stored_maint_key, new_stored_maint_key],
            :aggregate => :max)
        end

        notif_keys.each do |nk|
          dest = nk.sub(/^#{Regexp.escape(old_name)}:/, "#{current_name}:")
          redis.renamenx(nk, dest)
          redis.del(nk)
        end

        alerting_to_remove.each_pair do |alerting, chks|
          chks.each {|chk| redis.zrem(alerting, chk)}
        end

        alerting_to_add.each_pair do |alerting, chks|
          chks.each_pair {|chk, score| redis.zadd(alerting, score, chk)}
        end

        blocks_to_set.each_pair do |block_key, (timestamp, value)|
          redis.setex(block_key, (timestamp - Time.now.to_i), value)
        end

        keys_to_rename.each_pair do |old_key, new_key|
          redis.rename(old_key, new_key)
        end

        redis.del(*keys_to_delete) unless keys_to_delete.empty?

        redis.exec
      end

      # NB: If entities are renamed in imported data before they are
      # renamed in monitoring sources, data for old entities may still
      # arrive and be stored under those names.
      def self.add(entity, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        entity_name = entity['name']
        raise "Entity name not provided" if entity_name.nil? || entity_name.empty?

        entity_id = entity['id']

        if entity_id.nil?
          # likely to be from monitoring data

          # if an entity exists with the same name as the incoming data,
          # use its id; failing that allocate a random one
          entity_id = redis.get("entity_id:#{entity_name}")

          if entity_id.nil?
            entity_id = SecureRandom.uuid
            redis.set("entity_id:#{entity_name}", entity_id)
            redis.hset("entity:#{entity_id}", 'name', entity_name)
          end
        else
          # most likely from API import
          existing_name = redis.hget("entity:#{entity_id}", 'name')

          if existing_name.nil?

            # if there's an entity with a matching name, this will change its
            # id; if no entity exists it creates a new one
            redis.set("entity_id:#{entity_name}", entity_id)
            redis.hset("entity:#{entity_id}", 'name', entity_name)

          elsif existing_name != entity_name
            if redis.renamenx("entity_id:#{existing_name}", "entity_id:#{entity_name}")
              rename(existing_name, entity_name, :redis => redis) {
                redis.hset("entity:#{entity_id}", 'name', entity_name)
              }
            else
              merge(existing_name, entity_name, :redis => redis)
            end
          end
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

      def self.current_names(options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        redis.zrange('current_entities', 0, -1)
      end

      def self.find_all_with_failing_checks(options)
        raise "Redis connection not set" unless redis = options[:redis]
        Flapjack::Data::EntityCheck.find_current_failing_by_entity(:redis => redis).keys
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
