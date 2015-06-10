#!/usr/bin/env ruby

# NB: use of redis.keys probably indicates we should maintain a data
# structure to avoid the need for this type of query

require 'securerandom'
require 'set'

require 'ice_cube'
require 'swagger/blocks'

require 'zermelo/records/redis'

require 'flapjack/data/validators/id_validator'

require 'flapjack/data/medium'
require 'flapjack/data/rule'
require 'flapjack/data/tag'

require 'flapjack/gateways/jsonapi/data/associations'
require 'flapjack/gateways/jsonapi/data/join_descriptor'
require 'flapjack/gateways/jsonapi/data/method_descriptor'

module Flapjack

  module Data

    class Contact

      include Zermelo::Records::Redis
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false
      include Flapjack::Gateways::JSONAPI::Data::Associations
      include Swagger::Blocks

      define_attributes :name     => :string,
                        :timezone => :string

      index_by :name

      has_and_belongs_to_many :checks, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :contacts

      has_many :media, :class_name => 'Flapjack::Data::Medium',
        :inverse_of => :contact

      has_many :rules, :class_name => 'Flapjack::Data::Rule',
        :inverse_of => :contact, :after_remove => :clear_rule_alerting_media,
        :related_class_names => ['Flapjack::Data::Medium',
          'Flapjack::Data::Check', 'Flapjack::Data::ScheduledMaintenance']

      def self.clear_rule_alerting_media(contact_id, *r_ids)
        media_ids = Flapjack::Data::Rule.intersect(:id => r_ids).
          associated_ids_for(:media).values.reduce(:|)

        Flapjack::Data::Medium.intersect(:id => media_ids).each do |medium|
          medium.alerting_checks.clear
        end
      end

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

      def self.jsonapi_type
        self.name.demodulize.underscore
      end

      swagger_schema :Contact do
        key :required, [:id, :type, :name]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Contact.jsonapi_type.downcase]
        end
        property :name do
          key :type, :string
        end
        property :timezone do
          key :type, :string
          key :format, :tzinfo
        end
        property :links do
          key :"$ref", :ContactLinks
        end
      end

      swagger_schema :ContactLinks do
        key :required, [:self, :checks, :media, :rules]
        property :self do
          key :type, :string
          key :format, :url
        end
        property :checks do
          key :type, :string
          key :format, :url
        end
        property :media do
          key :type, :string
          key :format, :url
        end
        property :rules do
          key :type, :string
          key :format, :url
        end
      end

      swagger_schema :ContactCreate do
        key :required, [:type, :name]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Contact.jsonapi_type.downcase]
        end
        property :name do
          key :type, :string
        end
        property :timezone do
          key :type, :string
          key :format, :tzinfo
        end
        property :links do
          key :"$ref", :ContactChangeLinks
        end
      end

      swagger_schema :ContactUpdate do
        key :required, [:id, :type]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Contact.jsonapi_type.downcase]
        end
        property :name do
          key :type, :string
        end
        property :timezone do
          key :type, :string
          key :format, :tzinfo
        end
        property :links do
          key :"$ref", :ContactChangeLinks
        end
      end

      swagger_schema :ContactChangeLinks do
        property :media do
          key :"$ref", :jsonapi_MediaLinkage
        end
        property :rules do
          key :"$ref", :jsonapi_RulesLinkage
        end
      end

      def self.jsonapi_methods
        @jsonapi_methods ||= {
          :post => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:name, :timezone],
            :associations => [:media, :rules]
          ),
          :get => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:name, :timezone],
            :associations => [:checks, :media, :rules]
          ),
          :patch => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:name, :timezone],
            :associations => [:media, :rules]
          ),
          :delete => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
          ),
        }
      end

      def self.jsonapi_associations
        @jsonapi_associations ||= {
          :checks => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
            :post => false, :patch => false, :delete => false,
            :number => :multiple, :link => true, :include => true
          ),
          :media => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
            :number => :multiple, :link => true, :include => true
          ),
          :rules => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
            :number => :multiple, :link => true, :include => true
          )
        }
      end
    end
  end
end
