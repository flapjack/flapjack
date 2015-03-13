#!/usr/bin/env ruby

require 'zermelo/records/redis_record'

require 'flapjack/data/validators/id_validator'

require 'flapjack/gateways/jsonapi/data/associations'

module Flapjack
  module Data
    class ScheduledMaintenance

      include Zermelo::Records::RedisRecord
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false
      include Flapjack::Gateways::JSONAPI::Data::Associations
      include Swagger::Blocks

      define_attributes :start_time => :timestamp,
                        :end_time   => :timestamp,
                        :summary    => :string

      belongs_to :check_by_start, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :scheduled_maintenances_by_start

      belongs_to :check_by_end, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :scheduled_maintenances_by_end

      validates :start_time, :presence => true
      validates :end_time, :presence => true

      validates_with Flapjack::Data::Validators::IdValidator

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

      swagger_model :jsonapi_ScheduledMaintenance do
        key :id, :jsonapi_ScheduledMaintenance
        property :scheduled_maintenances do
          key :type, :ScheduledMaintenance
        end
      end

      swagger_model :jsonapi_ScheduledMaintenances do
        key :id, :jsonapi_ScheduledMaintenances
        property :scheduled_maintenances do
          key :type, :array
          items do
            key :type, :ScheduledMaintenance
          end
        end
      end

      swagger_model :ScheduledMaintenance do
        key :id, :ScheduledMaintenance
        key :required, [:start_time, :end_time]
        property :id do
          key :type, :string
        end
        property :start_time do
          key :type, :string
          key :format, :"date-time"
        end
        property :end_time do
          key :type, :string
          key :format, :"date-time"
        end
        property :links do
          key :"$ref", :ScheduledMaintenanceLinks
        end
      end

      swagger_model :ScheduledMaintenanceLinks do
        key :id, :ScheduledMaintenanceLinks
        property :check do
          key :type, :string
        end
      end

      def self.jsonapi_type
        self.name.demodulize.underscore
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