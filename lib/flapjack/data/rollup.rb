#!/usr/bin/env ruby

require 'swagger/blocks'

require 'zermelo/records/redis'

require 'flapjack/data/extensions/short_name'
require 'flapjack/data/validators/id_validator'

require 'flapjack/data/medium'
require 'flapjack/data/tag'

require 'flapjack/data/extensions/associations'
require 'flapjack/gateways/jsonapi/data/join_descriptor'
require 'flapjack/gateways/jsonapi/data/method_descriptor'

module Flapjack
  module Data
    class Rollup

      include Zermelo::Records::Redis
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false
      include Swagger::Blocks

      include Flapjack::Data::Extensions::Associations
      include Flapjack::Data::Extensions::ShortName

      define_attributes :threshold => :integer,
                        :last_type => :string

      belongs_to :medium, :class_name => 'Flapjack::Data::Medium',
        :inverse_of => :rollups

      belongs_to :tag, :class_name => 'Flapjack::Data::Tag',
        :inverse_of => :rollups

      validates :threshold, :presence => true,
        :numericality => {:greater_than => 0, :only_integer => true}

      swagger_schema :Rollup do
        key :required, [:id, :type, :threshold]
        property :id do
          key :type, :string
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Rollup.short_model_name.singular]
        end
        property :threshold do
          key :type, :integer
          key :minimum, 1
        end
        property :relationships do
          key :"$ref", :RollupLinks
        end
      end

      swagger_schema :RollupLinks do
        key :required, [:self, :media, :tags]
        property :self do
          key :type, :string
          key :format, :url
        end
        property :medium do
          key :type, :string
          key :format, :url
        end
        property :tag do
          key :type, :string
          key :format, :url
        end
      end

      swagger_schema :RollupCreate do
        key :required, [:type, :threshold]
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Rollup.short_model_name.singular]
        end
        property :threshold do
          key :type, :integer
          key :minimum, 1
        end
        property :relationships do
          key :"$ref", :RollupChangeLinks
        end
      end

      swagger_schema :RollupUpdate do
        key :required, [:id, :type]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Rollup.short_model_name.singular]
        end
        property :threshold do
          key :type, :integer
          key :minimum, 1
        end
        property :relationships do
          key :"$ref", :RollupChangeLinks
        end
      end

      swagger_schema :RollupChangeLinks do
        property :medium do
          key :"$ref", :jsonapi_MediaLinkage
        end
        property :tag do
          key :"$ref", :jsonapi_TagsLinkage
        end
      end

      def self.jsonapi_methods
        @jsonapi_methods ||= {
          :post => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:threshold]
          ),
          :get => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:threshold]
          ),
          :patch => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:threshold]
          ),
          :delete => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
          )
        }
      end

      def self.jsonapi_associations
        if @jsonapi_associations.nil?
          @jsonapi_associations = {
            :medium => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :post => true, :get => true, :patch => true, :delete => true,
              :number => :singular, :link => true, :includable => true
            ),
            :tag => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :post => true, :get => true, :patch => true, :delete => true,
              :number => :singular, :link => true, :includable => true
            )
          }
          populate_association_data(@jsonapi_associations)
        end
        @jsonapi_associations
      end
    end
  end
end
