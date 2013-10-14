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
                        :timestamp => :timestamp,
                        :notified  => :boolean,
                        :notification_times => :set

      index_by :state, :notified, :count

      belongs_to :entity_check, :class_name => 'Flapjack::Data::EntityCheckR'

      validate :state, :presence => true,
        :inclusion => { :in => [STATE_OK, STATE_WARNING,
                                STATE_CRITICAL, STATE_UNKNOWN] }
      validate :timestamp, :presence => true

      def self.ok_states
        [STATE_OK]
      end

      def self.failing_states
        [STATE_CRITICAL, STATE_WARNING, STATE_UNKNOWN]
      end

    end
  end
end