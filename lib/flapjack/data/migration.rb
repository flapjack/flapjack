#!/usr/bin/env ruby

require 'flapjack/data/contact'
require 'flapjack/data/entity_check'

require 'flapjack/data/semaphore'

module Flapjack
  module Data
    class Migration

      ENTITY_DATA_MIGRATION = 'entity_data_migration'

      # copied from jsonapi/contact_methods.rb, could extract both into separate file
      def self.obtain_semaphore(resource, description, options = {})
        raise "Redis connection not set" unless redis = options[:redis]

        logger = options[:logger]

        semaphore = nil
        strikes = 0
        begin
          semaphore = Flapjack::Data::Semaphore.new(resource, :redis => redis, :expiry => 300)
        rescue Flapjack::Data::Semaphore::ResourceLocked
          strikes += 1
          if strikes < 10
            sleep 2
            retry
          end
          sempahore = nil
        end

        if semaphore.nil?
          unless logger.nil?
            logger.fatal "Could not obtain lock for data migration (#{reason}). Ensure that " +
              "no other flapjack processes are running that might be executing " +
              "migrations, check logs for any exceptions, manually delete the " +
              "'#{resource}' key from your Flapjack Redis " +
              "database and try running Flapjack again."
          end
          raise "Unable to obtain semaphore #{resource}"
        end

        semaphore
      end

      def self.create_entity_ids_if_required(options = {})
        raise "Redis connection not set" unless redis = options[:redis]

        logger = options[:logger]

        return if redis.exists('created_ids_for_old_entities_without_ids')

        semaphore = obtain_semaphore(ENTITY_DATA_MIGRATION, 'entity id creation',
          :redis => redis, :logger => logger)

        begin
          logger.warn "Ensuring all entities have ids ..." unless logger.nil?

          Flapjack::Data::EntityCheck.find_current_names_by_entity(:redis => redis, :logger => logger).keys.each {|entity_name|
            entity = Flapjack::Data::Entity.find_by_name(entity_name, :create => true, :redis => redis, :logger => logger)
          }

          all_checks = Flapjack::Data::EntityCheck.all(:redis => redis, :logger => logger, :create_entity => true)

          redis.set('created_ids_for_old_entities_without_ids', 'true')
          logger.warn "Entity id creation complete."
        ensure
          semaphore.release
        end
      end

      def self.migrate_entity_check_data_if_required(options = {})
        raise "Redis connection not set" unless redis = options[:redis]

        logger = options[:logger]

        return if redis.exists('all_checks')

        semaphore = obtain_semaphore(ENTITY_DATA_MIGRATION, 'entity check data',
          :redis => redis, :logger => logger)

        begin
          check_names = redis.keys('check:*').map {|c| c.sub(/^check:/, '') } |
            Flapjack::Data::EntityCheck.find_current_names(:redis => redis)

          unless check_names.empty?
            logger.warn "Upgrading Flapjack's entity/check Redis indexes..." unless logger.nil?

            timestamp = Time.now.to_i

            check_names.each do |ecn|
              redis.zadd("all_checks", timestamp, ecn)
              entity_name, check = ecn.split(':', 2)
              redis.zadd("all_checks:#{entity_name}", timestamp, check)
              # not deleting the check hashes, they store useful data
            end
            logger.warn "Checks indexed." unless logger.nil?
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
            logger.warn "Entities indexed." unless logger.nil?
          end

          logger.warn "Indexing complete." unless logger.nil? || (check_names.empty? && entity_name_keys.empty?)
        ensure
          semaphore.release
        end
      end

      def self.clear_orphaned_entity_ids(options = {})
        raise "Redis connection not set" unless redis = options[:redis]

        logger = options[:logger]

        semaphore = obtain_semaphore(ENTITY_DATA_MIGRATION,
          'orphaned entity ids', :redis => redis, :logger => logger)

        begin
          logger.info "Checking for orphaned entity ids..." unless logger.nil?

          valid_entity_data = redis.hgetall('all_entity_ids_by_name')

          missing_ids = redis.hgetall('all_entity_names_by_id').reject {|e_id, e_name|
            valid_entity_data[e_name] == e_id
          }

          unless missing_ids.empty?
            logger.info "Clearing ids (#{missing_ids.inspect})" unless logger.nil?
            redis.hdel('all_entity_names_by_id', missing_ids.keys)
          end
        ensure
          semaphore.release
          logger.info "Finished checking for orphaned entity ids." unless logger.nil?
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

      def self.correct_notification_rule_contact_linkages(options = {})
        raise "Redis connection not set" unless redis = options[:redis]

        logger = options[:logger]

        return if redis.exists('corrected_notification_rule_contact_linkages')

        invalid_notification_rule_keys = redis.keys("notification_rule:*").select {|k|
          contact_id = redis.hget(k, 'contact_id')
          contact_id.nil? || contact_id.empty?
        }.collect {|nrk| nrk.sub(/^notification_rule:/, '') }

        unless invalid_notification_rule_keys.empty?
          Flapjack::Data::Contact.all(:redis => redis).each do |contact|
            correctable = contact.notification_rule_ids & invalid_notification_rule_keys
            next if correctable.empty?
            correctable.each {|ck| redis.hset("notification_rule:#{ck}", 'contact_id', contact.id) }
            logger.warn "Set contact #{contact.id} for rules #{correctable.join(', ')}" unless logger.nil?
          end
        end

        redis.set('corrected_notification_rule_contact_linkages', 'true')
      end

      def self.validate_scheduled_maintenance_periods(options = {})
        raise "Redis connection not set" unless redis = options[:redis]

        logger = options[:logger]

        return if redis.exists('validated_scheduled_maintenance_periods')

        Flapjack::Data::EntityCheck.all(:redis => redis).compact.select {|ec|
          ec.in_scheduled_maintenance?
        }.each do |check|
          check.update_current_scheduled_maintenance(:revalidate => true)
        end

        logger.warn "Validated scheduled maintenance period expiry" unless logger.nil?
        redis.set('validated_scheduled_maintenance_periods', 'true')
      end

    end
  end
end
