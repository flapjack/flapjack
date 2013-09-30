#!/usr/bin/env ruby

module Flapjack
  module Data
    class CheckStateR

      include Flapjack::Data::RedisRecord

      STATE_OK       = 'ok'
      STATE_WARNING  = 'warning'
      STATE_CRITICAL = 'critical'
      STATE_UNKNOWN  = 'unknown'

      define_attributes :state     => :string,
                        :summary   => :string,
                        :details   => :string,
                        :count     => :integer,
                        :timestamp => :timestamp

      belongs_to :entity_check, :class_name => 'Flapjack::Data::EntityCheckR'

      def self.ok_states
        [STATE_OK]
      end

      def self.failing_states
        [STATE_WARNING, STATE_CRITICAL, STATE_UNKNOWN]
      end

    end
  end
end