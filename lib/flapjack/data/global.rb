#!/usr/bin/env ruby

# Used for data that is 'global' to an instance of Flapjack's Executive component

require 'flapjack/data/entity_check'

module Flapjack

  module Data

    class Global

      def self.unacknowledged_failing_checks(options = {})
        raise "Redis connection not set" unless redis = options[:redis]

        redis.zrange('failed_checks', '0', '-1').reject {|entity_check|
          redis.exists(entity_check + ':unscheduled_maintenance')
        }.collect {|entity_check|
          Flapjack::Data::EntityCheck.for_event_id(entity_check, :redis => redis)
        }
      end

    end

  end

end