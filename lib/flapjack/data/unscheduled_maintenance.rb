#!/usr/bin/env ruby

require 'swagger/blocks'

require 'zermelo/records/redis_record'

require 'flapjack/data/validators/id_validator'

require 'flapjack/gateways/jsonapi/data/associations'

module Flapjack
  module Data
    class UnscheduledMaintenance

      include Zermelo::Records::RedisRecord
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false
      include Flapjack::Gateways::JSONAPI::Data::Associations
      include Swagger::Blocks

      define_attributes :start_time => :timestamp,
                        :end_time   => :timestamp,
                        :summary    => :string

      belongs_to :check_by_start, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :unscheduled_maintenances_by_start

      belongs_to :check_by_end, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :unscheduled_maintenances_by_end

      before_validation :ensure_start_time

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

      swagger_schema :UnscheduledMaintenance do
        key :required, [:id, :type, :start_time, :end_time]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::UnscheduledMaintenance.jsonapi_type.downcase]
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
          key :"$ref", :UnscheduledMaintenanceLinks
        end
      end

      swagger_schema :UnscheduledMaintenanceLinks do
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

      swagger_schema :UnscheduledMaintenanceCreate do
        key :required, [:type, :start_time, :end_time]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::UnscheduledMaintenance.jsonapi_type.downcase]
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

      swagger_schema :UnscheduledMaintenanceUpdate do
        key :required, [:id, :type]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::UnscheduledMaintenance.jsonapi_type.downcase]
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
          key :"$ref", :UnscheduledMaintenanceUpdateLinks
        end
      end

      swagger_schema :UnscheduledMaintenanceUpdateLinks do
        property :check do
          key :"$ref", :CheckReference
        end
      end

      def self.jsonapi_methods
        [:post, :get, :patch, :delete]
      end

      def self.jsonapi_attributes
        {
          :post  => [:start_time, :end_time, :summary],
          :get   => [:start_time, :end_time, :summary],
          :patch => [:start_time, :end_time, :summary]
        }
      end

      def self.jsonapi_associations
        {
          :singular => [{:check_by_start => :check, :check_by_end => :check}],
          :multiple => []
        }
      end

      private

      def ensure_start_time
        self.start_time ||= Time.now
      end

    end
  end
end
