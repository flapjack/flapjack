#!/usr/bin/env ruby

require 'set'

require 'ice_cube'
require 'swagger/blocks'

require 'flapjack/utility'

require 'zermelo/records/redis'

require 'flapjack/data/extensions/short_name'
require 'flapjack/data/validators/id_validator'

require 'flapjack/data/time_restriction'

require 'flapjack/data/extensions/associations'
require 'flapjack/data/extensions/rule_matcher'
require 'flapjack/gateways/jsonapi/data/join_descriptor'
require 'flapjack/gateways/jsonapi/data/method_descriptor'

module Flapjack
  module Data
    class Rejector

      extend Flapjack::Utility

      include Zermelo::Records::Redis
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false
      include Swagger::Blocks

      include Flapjack::Data::Extensions::Associations
      include Flapjack::Data::Extensions::RuleMatcher
      include Flapjack::Data::Extensions::ShortName

      belongs_to :contact, :class_name => 'Flapjack::Data::Contact',
        :inverse_of => :rejectors

      has_and_belongs_to_many :media, :class_name => 'Flapjack::Data::Medium',
        :inverse_of => :rejectors, :after_add => :media_added,
        :after_remove => :media_removed

      has_and_belongs_to_many :tags, :class_name => 'Flapjack::Data::Tag',
        :inverse_of => :rejectors, :after_add => :tags_added,
        :after_remove => :tags_removed

      swagger_schema :Rejector do
        key :required, [:id, :type]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Rejector.short_model_name.singular]
        end
        property :name do
          key :type, :string
        end
        property :all do
          key :type, :boolean
        end
        property :conditions_list do
          key :type, :string
        end
        property :time_restrictions do
          key :type, :array
          items do
            key :"$ref", :TimeRestrictions
          end
        end
        property :relationships do
          key :"$ref", :RejectorLinks
        end
      end

      swagger_schema :RejectorLinks do
        key :required, [:self, :contact, :media, :tags]
        property :self do
          key :type, :string
          key :format, :url
        end
        property :contact do
          key :type, :string
          key :format, :url
        end
        property :media do
          key :type, :string
          key :format, :url
        end
        property :tags do
          key :type, :string
          key :format, :url
        end
      end

      swagger_schema :RejectorCreate do
        key :required, [:type]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Rejector.short_model_name.singular]
        end
        property :name do
          key :type, :string
        end
        property :all do
          key :type, :boolean
        end
        property :conditions_list do
          key :type, :string
        end
        property :time_restrictions do
          key :type, :array
          items do
            key :"$ref", :TimeRestrictions
          end
        end
        property :relationships do
          key :"$ref", :RejectorChangeLinks
        end
      end

      swagger_schema :RejectorUpdate do
        key :required, [:id, :type]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Rejector.short_model_name.singular]
        end
        property :name do
          key :type, :string
        end
        property :all do
          key :type, :boolean
        end
        property :conditions_list do
          key :type, :string
        end
        property :time_restrictions do
          key :type, :array
          items do
            key :"$ref", :TimeRestrictions
          end
        end
        property :relationships do
          key :"$ref", :RejectorChangeLinks
        end
      end

      swagger_schema :RejectorChangeLinks do
        property :contact do
          key :"$ref", :jsonapi_ContactLinkage
        end
        property :media do
          key :"$ref", :jsonapi_MediaLinkage
        end
        property :tags do
          key :"$ref", :jsonapi_TagsLinkage
        end
      end

      def self.jsonapi_methods
        @jsonapi_methods ||= {
          :post => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:name, :all, :conditions_list, :time_restrictions]
          ),
          :get => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:name, :all, :conditions_list, :time_restrictions]
          ),
          :patch => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:name, :all, :conditions_list, :time_restrictions]
          ),
          :delete => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
          )
        }
      end

      def self.jsonapi_associations
        if @jsonapi_associations.nil?
          @jsonapi_associations = {
            :contact => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :post => true, :get => true,
              :number => :singular, :link => true, :includable => true
            ),
            :media => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :post => true, :get => true, :patch => true, :delete => true,
              :number => :multiple, :link => true, :includable => true
            ),
            :tags => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :post => true, :get => true, :patch => true, :delete => true,
              :number => :multiple, :link => true, :includable => true
            )
          }
          populate_association_data(@jsonapi_associations)
        end
        @jsonapi_associations
      end

    end
  end
end

