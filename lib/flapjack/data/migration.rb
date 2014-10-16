#!/usr/bin/env ruby

module Flapjack
  module Data
    class Migration

      def self.migrate_entity_check_data_if_required(options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        return if redis.exists('all_checks')

        check_names = redis.keys('check:*').map {|c| c.sub(/^check:/, '') } |
          Flapjack::Data::EntityCheck.find_current_names(:redis => redis)

        unless check_names.empty?
          timestamp = Time.now.to_i

          check_names.each do |ecn|
            @redis.zadd("all_checks", timestamp, ecn)
            entity_name, check = cn.split(':', 2)
            @redis.zadd("all_checks:#{entity_name}", timestamp, check)
            # not deleting the check hashes, they store useful data
          end
        end

        entity_name_keys = redis.keys("entity_id:*")
        unless entity_name_keys.empty?
          ids = redis.mget(*entity_name_keys)

          entity_name_keys.each do |enk|
            enk =~ /^entity_id:(.+)$/; entity_name = $1; entity_id = ids.shift

            redis.hset('all_entity_names_by_id', entity_id, entity_name)
            redis.hset('all_entity_ids_by_name', entity_name, entity_id)

            redis.del(enk)
            redis.del("entity:#{entity_id}")
          end
        end
      end

      def self.refresh_archive_index(options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        archive_keys = redis.keys('events_archive:*')
        if archive_keys.empty?
          redis.del('known_events_archive_keys')
          return
        end

        grouped_keys = archive_keys.group_by do |ak|
          (redis.llen(ak) > 0) ? 'add' : 'remove'
        end

        {'remove' => :srem, 'add' => :sadd}.each_pair do |k, cmd|
          next unless grouped_keys.has_key?(k) && !grouped_keys[k].empty?
          redis.send(cmd, 'known_events_archive_keys', grouped_keys[k])
        end
      end

      def self.purge_expired_archive_index(options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        return unless redis.exists('known_events_archive_keys')

        redis.smembers('known_events_archive_keys').each do |ak|
          redis.srem('known_events_archive_keys', ak) unless redis.exists(ak)
        end
      end

    end
  end
end