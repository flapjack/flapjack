#!/usr/bin/env ruby

module Flapjack
  module Data
    class Migration

      def self.refresh_archive_index(options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        events_keys = redis.keys('events_archive:*')
        if events_keys.empty?
          redis.del('known_events_archive_keys')
          return
        end

        archive_keys = events_keys.group_by do |ak|
          (redis.llen(ak) > 0) ? 't' : 'f'
        end

        {'f' => :srem, 't' => :sadd}.each_pair do |k, cmd|
          next unless archive_keys.has_key?(k) && !archive_keys[k].empty?
          redis.send(cmd, 'known_events_archive_keys', archive_keys[k])
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