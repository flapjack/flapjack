#!/usr/bin/env ruby

# NB: use of redis.keys probably indicates we should maintain a data
# structure to avoid the need for this type of query


require 'set'
require 'securerandom'

require 'ice_cube'

require 'zermelo/records/redis_record'

require 'flapjack/data/validators/id_validator'

require 'flapjack/data/medium'
require 'flapjack/data/rule'
require 'flapjack/data/tag'

require 'flapjack/gateways/jsonapi/data/associations'

module Flapjack

  module Data

    class Contact

      include Zermelo::Records::RedisRecord
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false
      include Flapjack::Gateways::JSONAPI::Data::Associations
      include Swagger::Blocks

      define_attributes :name     => :string,
                        :timezone => :string

      index_by :name

      has_many :media, :class_name => 'Flapjack::Data::Medium',
        :inverse_of => :contact

      has_many :rules, :class_name => 'Flapjack::Data::Rule',
        :inverse_of => :contact

      validates_with Flapjack::Data::Validators::IdValidator

      validates_each :timezone, :allow_nil => true do |record, att, value|
        record.errors.add(att, 'must be a valid time zone string') if ActiveSupport::TimeZone[value].nil?
      end

      before_destroy :remove_child_records
      def remove_child_records
        self.media.each  {|medium| medium.destroy }
        self.rules.each  {|rule|   rule.destroy }
      end

      def time_zone
        return nil if self.timezone.nil?
        ActiveSupport::TimeZone[self.timezone]
      end

      def checks
        route_ids_by_rule_id = self.rules.associated_ids_for(:routes)
        route_ids = route_ids_by_rule_id.values.reduce(&:|)

        check_ids = Flapjack::Data::Route.intersect(:id => route_ids).
          associated_ids_for(:checks).values.reduce(:|)

        Flapjack::Data::Check.intersect(:id => check_ids)
      end

      swagger_model :jsonapi_Contact do
        key :id, :jsonapi_Contact
        property :contacts do
          key :type, :Contact
        end
      end

      swagger_model :jsonapi_Contacts do
        key :id, :jsonapi_Contacts
        property :contacts do
          key :type, :array
          items do
            key :type, :Contact
          end
        end
      end

      swagger_model :Contact do
        key :id, :Contact
        key :required, [:name]
        property :id do
          key :type, :string
        end
        property :name do
          key :type, :string
        end
        property :timezone do
          key :type, :string
        end
        property :links do
          key :"$ref", :ContactLinks
        end
      end

      swagger_model :ContactLinks do
        key :id, :ContactLinks
        property :media do
          key :type, :array
          items do
            key :type, :string
          end
        end
        property :rules do
          key :type, :array
          items do
            key :type, :string
          end
        end
      end

      def self.jsonapi_type
        self.name.demodulize.underscore
      end

      def self.jsonapi_attributes
        [:name, :timezone]
      end

      def self.jsonapi_search_string_attributes
        [:name, :timezone]
      end

      def self.jsonapi_singular_associations
        []
      end

      def self.jsonapi_multiple_associations
        [:media, :rules]
      end

    end
  end
end
