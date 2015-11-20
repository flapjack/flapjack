#!/usr/bin/env ruby

require 'swagger/blocks'

require 'zermelo/records/redis'

require 'flapjack/data/extensions/short_name'
require 'flapjack/data/validators/id_validator'

require 'flapjack/data/extensions/associations'
require 'flapjack/gateways/jsonapi/data/join_descriptor'
require 'flapjack/gateways/jsonapi/data/method_descriptor'

module Flapjack
  module Data
    class UnscheduledMaintenance

      include Zermelo::Records::RedisSortedSet
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false
      include Swagger::Blocks

      include Flapjack::Data::Extensions::Associations
      include Flapjack::Data::Extensions::ShortName

      define_attributes :start_time => :timestamp,
                        :end_time   => :timestamp,
                        :summary    => :string

      define_sort_attribute :start_time

      belongs_to :check, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :unscheduled_maintenances

      # TODO :check before_set -- should fail if already set

      range_index_by :start_time, :end_time

      before_validation :ensure_start_time

      validates :start_time, :presence => true
      validates :end_time, :presence => true

      validates_with Flapjack::Data::Validators::IdValidator

      def duration
        self.end_time - self.start_time
      end

      swagger_schema :UnscheduledMaintenance do
        key :required, [:id, :type, :start_time, :end_time]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::UnscheduledMaintenance.short_model_name.singular]
        end
        property :start_time do
          key :type, :string
          key :format, :"date-time"
        end
        property :end_time do
          key :type, :string
          key :format, :"date-time"
        end
        property :relationships do
          key :"$ref", :UnscheduledMaintenanceLinks
        end
      end

      swagger_schema :UnscheduledMaintenanceLinks do
        key :required, [:check]
        property :check do
          key :"$ref", :CheckLinkage
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
          key :enum, [Flapjack::Data::UnscheduledMaintenance.short_model_name.singular]
        end
        property :end_time do
          key :type, :string
          key :format, :"date-time"
        end
      end

      def self.swagger_included_classes
        # hack -- hardcoding for now
        [
          Flapjack::Data::Check,
          Flapjack::Data::Contact,
          Flapjack::Data::Medium,
          Flapjack::Data::Rule,
          Flapjack::Data::ScheduledMaintenance,
          Flapjack::Data::State,
          Flapjack::Data::Tag,
          Flapjack::Data::UnscheduledMaintenance
        ]
      end

      def self.jsonapi_methods
        @jsonapi_methods ||= {
          :get => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:start_time, :end_time, :summary],
            :descriptions => {
              :singular => "Get data for an un scheduled maintenance period.",
              :multiple => "Get data for multiple unscheduled maintenance periods."
            }
          ),
          :patch => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:start_time, :end_time, :summary],
            :descriptions => {
              :singular => "Update data for an unscheduled maintenance period.",
              :multiple => "Update data for unscheduled maintenance periods.",
            }
          ),
          :delete => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :descriptions => {
              :singular => "Delete an scheduled maintenance period.",
              :multiple => "Delete unscheduled maintenance periods."
            }
          )
        }
      end

      def self.jsonapi_associations
        unless instance_variable_defined?('@jsonapi_associations')
          @jsonapi_associations ||= {
            :check => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :get => true,
              :number => :singular, :link => true, :includable => true,
              :descriptions => {
                :get => "Returns the check an unscheduled maintenance period applies to."
              }
            )
          }
          populate_association_data(@jsonapi_associations)
        end
        @jsonapi_associations
      end

      private

      def ensure_start_time
        self.start_time ||= Time.now
      end

    end
  end
end
