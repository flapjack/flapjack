#!/usr/bin/env ruby

require 'zermelo/records/redis'

require 'flapjack/data/validators/id_validator'

require 'flapjack/gateways/jsonapi/data/associations'

module Flapjack
  module Data
    class ScheduledMaintenance
      include Zermelo::Records::Redis
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false
      include Flapjack::Gateways::JSONAPI::Data::Associations
      include Swagger::Blocks

      define_attributes :start_time => :timestamp,
                        :end_time   => :timestamp,
                        :summary    => :string

      belongs_to :check, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :scheduled_maintenances

      range_index_by :start_time, :end_time

      validates :start_time, :presence => true
      validates :end_time, :presence => true

      validates_with Flapjack::Data::Validators::IdValidator

      def duration
        self.end_time - self.start_time
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
        property :links do
          key :"$ref", :ScheduledMaintenanceChangeLinks
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
          key :"$ref", :ScheduledMaintenanceChangeLinks
        end
      end

      swagger_schema :ScheduledMaintenanceChangeLinks do
        property :check do
          key :"$ref", :jsonapi_CheckLinkage
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

      def self.jsonapi_extra_locks
        {
          :post   => [],
          :get    => [],
          :patch  => [],
          :delete => []
        }
      end

      # read-only by definition; singular & multiple hashes of
      # method_name => [other classes to lock]
      def self.jsonapi_linked_methods
        {
          :singular => {
          },
          :multiple => {
          }
        }
      end

      def self.jsonapi_associations
        {
          :read_only => {
            :singular => [],
            :multiple => []
          },
          :read_write => {
            :singular => [:check],
            :multiple => []
          }
        }
      end
    end
  end
end