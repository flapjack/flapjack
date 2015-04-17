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

      def self.jsonapi_type
        self.name.demodulize.underscore
      end

      swagger_schema :ScheduledMaintenance do
        key :required, [:id, :type, :start_time, :end_time]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::ScheduledMaintenance.jsonapi_type.downcase]
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

      swagger_schema :ScheduledMaintenanceLinks do
        key :required, [:self, :check]
        property :self do
          key :type, :string
          key :format, :url
        end
        property :check do
          key :type, :string
          key :format, :url
        end
      end

      swagger_schema :ScheduledMaintenanceCreate do
        key :required, [:type, :start_time, :end_time]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::ScheduledMaintenance.jsonapi_type.downcase]
        end
        property :start_time do
          key :type, :string
          key :format, :"date-time"
        end
        property :end_time do
          key :type, :string
          key :format, :"date-time"
        end
      end

      swagger_schema :ScheduledMaintenanceUpdate do
        key :required, [:id, :type, :links]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::ScheduledMaintenance.jsonapi_type.downcase]
        end
        property :links do
          key :"$ref", :ScheduledMaintenanceUpdateLinks
        end
      end

      swagger_schema :ScheduledMaintenanceUpdateLinks do
        key :required, [:check]
        property :check do
          key :"$ref", :CheckReference
        end
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