#!/usr/bin/env ruby

require 'securerandom'
require 'set'

require 'ice_cube'
require 'swagger/blocks'

require 'zermelo/records/redis'

require 'flapjack/data/extensions/short_name'
require 'flapjack/data/validators/id_validator'

require 'flapjack/data/extensions/associations'
require 'flapjack/gateways/jsonapi/data/join_descriptor'
require 'flapjack/gateways/jsonapi/data/method_descriptor'

module Flapjack

  module Data

    class Contact

      include Zermelo::Records::RedisSet
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false
      include Swagger::Blocks

      include Flapjack::Data::Extensions::Associations
      include Flapjack::Data::Extensions::ShortName

      define_attributes :name     => :string,
                        :timezone => :string

      index_by :name

      has_many :rules, :class_name => 'Flapjack::Data::Rule',
        :inverse_of => :contact

      has_many :media, :class_name => 'Flapjack::Data::Medium',
        :inverse_of => :contact

      has_and_belongs_to_many :tags, :class_name => 'Flapjack::Data::Tag',
        :inverse_of => :contacts

      validates_with Flapjack::Data::Validators::IdValidator

      validates_each :timezone, :allow_nil => true do |record, att, value|
        record.errors.add(att, 'must be a valid time zone string') if ActiveSupport::TimeZone[value].nil?
      end

      before_destroy :remove_child_records
      def remove_child_records
        self.media.each  {|medium| medium.destroy }
        self.rules.each  {|rule|   rule.destroy   }
      end

      def time_zone
        return nil if self.timezone.nil?
        ActiveSupport::TimeZone[self.timezone]
      end

      def checks
        time = Time.now

        global_acceptors = self.rules.intersect(:enabled => true,
          :blackhole => false, :strategy => 'global')

        global_rejector_ids = self.rules.intersect(:enabled => true,
          :blackhole => true, :strategy => 'global').select {|rejector|

          rejector.is_occurring_at?(time, timezone)
        }.map(&:id)

        # global blackhole
        return Flapjack::Data::Check.empty unless global_rejector_ids.empty?

        tag_rejector_ids = self.rules.intersect(:enabled => true,
          :blackhole => true, :strategy => ['any_tag', 'all_tags', 'no_tag']).select {|rejector|

          rejector.is_occurring_at?(time, timezone)
        }.map(&:id)

        tag_acceptors = self.rules.intersect(:enabled => true, :blackhole => false,
          :strategy => ['any_tag', 'all_tags', 'no_tag']).select {|acceptor|

          acceptor.is_occurring_at?(time, timezone)
        }

        # no positives
        return Flapjack::Data::Check.empty if tag_acceptors.empty?


        # initial scope is all enabled
        linked_checks = Flapjack::Data::Check.intersect(:enabled => true)

        if global_acceptors.empty?
          # if no global acceptor, scope by matching tags
          tag_acceptor_checks = Flapjack::Data::Rule.matching_checks(tag_acceptors.map(&:id))
          linked_checks = linked_checks.intersect(:id => tag_acceptor_checks)
        end

        # then exclude by checks with tags matching rejector, if any
        tag_rejector_checks = Flapjack::Data::Rule.matching_checks(tag_rejector_ids)
        unless tag_rejector_checks.empty?
          linked_checks = linked_checks.diff(:id => tag_rejector_checks)
        end

        linked_checks
      end

      swagger_schema :Contact do
        key :required, [:id, :type, :name]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Contact.short_model_name.singular]
        end
        property :name do
          key :type, :string
        end
        property :timezone do
          key :type, :string
          key :format, :tzinfo
        end
        property :relationships do
          key :"$ref", :ContactLinks
        end
      end

      swagger_schema :ContactLinks do
        key :required, [:checks, :media, :rules]
        property :checks do
          key :"$ref", :ChecksLinkage
        end
        property :media do
          key :"$ref", :MediaLinkage
        end
        property :rules do
          key :"$ref", :RulesLinkage
        end
        property :tags do
          key :"$ref", :TagsLinkage
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
          key :enum, [Flapjack::Data::Contact.short_model_name.singular]
        end
        property :name do
          key :type, :string
        end
        property :timezone do
          key :type, :string
          key :format, :tzinfo
        end
        property :relationships do
          key :"$ref", :ContactCreateLinks
        end
      end

      swagger_schema :ContactCreateLinks do
        property :tags do
          key :"$ref", :data_TagsReference
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
          key :enum, [Flapjack::Data::Contact.short_model_name.singular]
        end
        property :name do
          key :type, :string
        end
        property :timezone do
          key :type, :string
          key :format, :tzinfo
        end
        property :relationships do
          key :"$ref", :ContactUpdateLinks
        end
      end

      swagger_schema :ContactUpdateLinks do
        property :media do
          key :"$ref", :data_MediaReference
        end
        property :rules do
          key :"$ref", :data_RulesReference
        end
        property :tags do
          key :"$ref", :data_TagsReference
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
          :post => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:name, :timezone],
            :descriptions => {
              :singular => "Create a contact.",
              :multiple => "Create contacts."
            }
          ),
          :get => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:name, :timezone],
            :descriptions => {
              :singular => "Get data for a contact.",
              :multiple => "Get data for multiple contacts."
            }
          ),
          :patch => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:name, :timezone],
            :descriptions => {
              :singular => "Update a contact record.",
              :multiple => "Update contact records."
            }
          ),
          :delete => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :descriptions => {
              :singular => "Delete a contact.",
              :multiple => "Delete contacts."
            }
          ),
        }
      end

      def self.jsonapi_associations
        unless instance_variable_defined?('@jsonapi_associations')
          @jsonapi_associations = {
            :checks => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :get => true,
              :number => :multiple, :link => true, :includable => true,
              :type => 'check',
              :klass => Flapjack::Data::Check,
              :descriptions => {
                :get => "Returns checks which this contact's notification " \
                        "rules allow it to receive notifications."
              }
            ),
            :media => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :get => true,
              :number => :multiple, :link => true, :includable => true,
              :descriptions => {
                :get => "Returns media belonging to the contact."
              }
            ),
            :rules => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :get => true,
              :number => :multiple, :link => true, :includable => true,
              :descriptions => {
                :get => "Returns rules belonging to the contact."
              }
            ),
            :tags => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :post => true, :get => true, :patch => true, :delete => true,
              :number => :multiple, :link => true, :includable => true,
              :descriptions => {
                :post => "Associate tags with this contact.",
                :get => "Returns all tags linked to this contact.",
                :patch => "Update the tags associated with this contact.",
                :delete => "Delete associations between tags and this contact."
              }
            )
          }
          populate_association_data(@jsonapi_associations)
        end
        @jsonapi_associations
      end
    end
  end
end
