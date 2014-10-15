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

    end
  end
end