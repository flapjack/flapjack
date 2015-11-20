#!/usr/bin/env ruby

require 'swagger/blocks'

require 'zermelo/records/redis'

require 'flapjack/data/extensions/associations'
require 'flapjack/data/extensions/short_name'
require 'flapjack/data/validators/id_validator'

require 'flapjack/gateways/jsonapi/data/method_descriptor'

module Flapjack
  module Data
    class Statistic

      # FIXME: add an administrative function to reset global or
      # instance Statistic objects

      include Zermelo::Records::RedisSet
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false
      include Swagger::Blocks

      include Flapjack::Data::Extensions::Associations
      include Flapjack::Data::Extensions::ShortName

      define_attributes :instance_name  => :string,
                        :created_at     => :timestamp,
                        :all_events     => :integer,
                        :ok_events      => :integer,
                        :failure_events => :integer,
                        :action_events  => :integer,
                        :invalid_events => :integer

      index_by :instance_name

      validates :instance_name, :presence => true
      validates :created_at, :presence => true

      [:all_events, :ok_events, :failure_events, :action_events,
       :invalid_events].each do |evt|

        validates evt, :presence => true,
          :numericality => {:greater_than_or_equal_to => 0, :only_integer => true}
      end

      swagger_schema :Statistic do
        key :required, [:id, :type, :instance_name, :created_at, :all_events,
                        :ok_events, :failure_events, :action_events]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Statistic.short_model_name.singular]
        end
        property :instance_name do
          key :type, :string
        end
        property :created_at do
          key :type, :string
          key :format, :'date-time'
        end
        property :all_events do
          key :type, :integer
          key :minimum, 0
        end
        property :ok_events do
          key :type, :integer
          key :minimum, 0
        end
        property :failure_events do
          key :type, :integer
          key :minimum, 0
        end
        property :action_events do
          key :type, :integer
          key :minimum, 0
        end
        property :invalid_events do
          key :type, :integer
          key :minimum, 0
        end
      end

      def self.swagger_included_classes
        # hack -- hardcoding for now
        []
      end

      def self.jsonapi_methods
        @jsonapi_methods ||= {
          :get => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:instance_name, :created_at, :all_events,
                            :ok_events, :failure_events, :action_events,
                            :invalid_events],
            :descriptions => {
              :multiple => "Returns global or per-instance event statistics.",
              :singular => "Returns a single event statistics data object."
            }
          )
        }
      end

      def self.jsonapi_associations
        @jsonapi_associations ||= {}
      end
    end
  end
end