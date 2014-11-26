#!/usr/bin/env ruby

require 'sandstorm/records/redis_record'

module Flapjack
  module Data
    class UnscheduledMaintenance

      include Sandstorm::Records::RedisRecord

      define_attributes :start_time => :timestamp,
                        :end_time   => :timestamp,
                        :summary    => :string,
                        :notified   => :boolean,
                        :last_notification_count => :integer

      index_by :notified

      validates :start_time, :presence => true
      validates :end_time, :presence => true

      belongs_to :check_by_start, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :unscheduled_maintenances_by_start

      belongs_to :check_by_end, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :unscheduled_maintenances_by_end

      def duration
        self.end_time - self.start_time
      end

      def check
        self.check_by_start
      end

      def check=(c)
        self.check_by_start = c
        self.check_by_end   = c
      end

      def self.jsonapi_attributes
        [:start_time, :end_time, :summary]
      end

      def self.jsonapi_singular_associations
        [{:check_by_start => :check, :check_by_end => :check}]
      end

      def self.jsonapi_multiple_associations
        []
      end
    end
  end
end