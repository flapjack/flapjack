#!/usr/bin/env ruby

require 'sandstorm/records/redis_record'

module Flapjack
  module Data
    class ScheduledMaintenance

      include Sandstorm::Records::RedisRecord

      define_attributes :start_time => :timestamp,
                        :end_time   => :timestamp,
                        :summary    => :string

      validates :start_time, :presence => true
      validates :end_time, :presence => true

      belongs_to :check_by_start, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :scheduled_maintenances_by_start

      belongs_to :check_by_end, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :scheduled_maintenances_by_end

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

      def self.as_jsonapi(fields, unwrap, *scheduled_maintenances)
        return [] if scheduled_maintenances.empty?
        sm_ids = scheduled_maintenances.map(&:id)

        whitelist = [:id, :start_time, :end_time, :summary]

        jsonapi_fields = if fields.nil?
          whitelist
        else
          Set.new(fields).add(:id).keep_if {|f| whitelist.include?(f) }.to_a
        end

        check_ids = Flapjack::Data::Check.intersect(:id => sm_ids).
                      associated_ids_for(:check_by_start)

        data = scheduled_maintenances.collect do |sm|
          sm.as_json(:only => jsonapi_fields).merge(:links => {
            :check => check_ids[sm.id]
          })
        end
        return data unless (data.size == 1) && unwrap
        data.first
      end

    end
  end
end