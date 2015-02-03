#!/usr/bin/env ruby

require 'eventmachine'
# the redis/synchrony gems need to be required in this particular order, see
# the redis-rb README for details
require 'hiredis'
require 'em-synchrony'
require 'redis/connection/synchrony'
require 'redis'

require 'em-synchrony/connection_pool'

require 'flapjack/data/migration'

module Flapjack
  class RedisPool < EventMachine::Synchrony::ConnectionPool

    def initialize(opts = {})
      config = opts.delete(:config)
      @size  = opts[:size] || 5
      logger = opts[:logger]
      super(:size => @size) {
        redis = ::Redis.new(config)
        Flapjack::Data::Migration.correct_notification_rule_contact_linkages(:redis => redis,
          :logger => logger)
        Flapjack::Data::Migration.migrate_entity_check_data_if_required(:redis => redis,
          :logger => logger)
        Flapjack::Data::Migration.create_entity_ids_if_required(:redis => redis,
          :logger => logger)
        Flapjack::Data::Migration.clear_orphaned_entity_ids(:redis => redis,
          :logger => logger)
        Flapjack::Data::Migration.refresh_archive_index(:redis => redis)
        Flapjack::Data::Migration.validate_scheduled_maintenance_periods(:redis => redis,
          :logger => logger)
        redis
      }
    end

  end
end
