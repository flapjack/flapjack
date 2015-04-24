#!/usr/bin/env ruby

require 'swagger/blocks'

require 'zermelo/records/redis_record'

require 'flapjack/data/validators/id_validator'

require 'flapjack/gateways/jsonapi/data/associations'

module Flapjack
  module Data
    class Statistics

      # FIXME: add an administrative function to reset global or
      # instance Statistics objects

      include Zermelo::Records::RedisRecord
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false
      include Flapjack::Gateways::JSONAPI::Data::Associations
      include Swagger::Blocks

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

      def self.jsonapi_type
        self.name.demodulize.underscore
      end

      swagger_schema :Statistics do
        key :required, [:id, :type, :instance_name, :all_events, :ok_events,
                        :failure_events, :action_events]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Medium.jsonapi_type.downcase]
        end
        property :instance_name do
          key :type, :string
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

      def self.jsonapi_attributes
        {
          :post  => [],
          :get   => [:instance_name, :all_events, :ok_events,
                     :failure_events, :action_events, :invalid_events],
          :patch => []
        }
      end

      def self.jsonapi_associations
        {
          :singular => [],
          :multiple => []
        }
      end
    end
  end
end