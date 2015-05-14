#!/usr/bin/env ruby

require 'swagger/blocks'

require 'zermelo/records/redis'

require 'flapjack/data/validators/id_validator'

require 'flapjack/gateways/jsonapi/data/associations'

module Flapjack
  module Data
    class Statistic

      # FIXME: add an administrative function to reset global or
      # instance Statistic objects

      include Zermelo::Records::Redis
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

      swagger_schema :Statistic do
        key :required, [:id, :type, :instance_name, :created_at, :all_events,
                        :ok_events, :failure_events, :action_events]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Statistic.jsonapi_type.downcase]
        end
        property :instance_name do
          key :type, :string
        end
        # property :created_at do
        #   key :type, :timestamp
        # end
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

      def self.jsonapi_methods
        [:get]
      end

      def self.jsonapi_attributes
        {
          :get   => [:instance_name, :created_at, :all_events, :ok_events,
                     :failure_events, :action_events, :invalid_events],
        }
      end

      def self.jsonapi_extra_locks
        {
          :get    => []
        }
      end

      def self.jsonapi_associations
        {
          :read_only => {
            :singular => [],
            :multiple => []
          }
        }
      end
    end
  end
end