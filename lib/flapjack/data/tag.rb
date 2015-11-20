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
    class Tag

      include Zermelo::Records::RedisSet
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false
      include Swagger::Blocks

      include Flapjack::Data::Extensions::Associations
      include Flapjack::Data::Extensions::ShortName

      define_attributes :name => :string

      has_and_belongs_to_many :checks,
        :class_name => 'Flapjack::Data::Check', :inverse_of => :tags

      has_and_belongs_to_many :contacts,
        :class_name => 'Flapjack::Data::Contact', :inverse_of => :tags

      has_and_belongs_to_many :rules,
        :class_name => 'Flapjack::Data::Rule', :inverse_of => :tags

      unique_index_by :name

      validates_with Flapjack::Data::Validators::IdValidator

      validates :name, :presence => true,
        :format => /\A[a-z0-9\-_\.\|]+\z/i

      def scheduled_maintenances
        sm_assocs = self.checks.associations_for(:scheduled_maintenances).
          values

        Flapjack::Data::ScheduledMaintenance.intersect(:id => sm_assocs)
      end

      def states
        st_assocs = self.checks.associations_for(:states).
          values

        Flapjack::Data::State.intersect(:id => st_assocs)
      end

      def unscheduled_maintenances
        usm_assocs = self.checks.associations_for(:unscheduled_maintenances).
          values

        Flapjack::Data::UnscheduledMaintenance.intersect(:id => usm_assocs)
      end

      swagger_schema :Tag do
        key :required, [:id, :type, :name]
        property :id do
          key :type, :string
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Tag.short_model_name.singular]
        end
        property :name do
          key :type, :string
        end
        property :relationships do
          key :"$ref", :TagLinks
        end
      end

      swagger_schema :TagLinks do
        property :checks do
          key :"$ref", :ChecksLinkage
        end
        property :contacts do
          key :"$ref", :ContactsLinkage
        end
        property :rules do
          key :"$ref", :RulesLinkage
        end
        property :scheduled_maintenances do
          key :"$ref", :ScheduledMaintenancesLinkage
        end
        property :states do
          key :"$ref", :StatesLinkage
        end
        property :unscheduled_maintenances do
          key :"$ref", :UnscheduledMaintenancesLinkage
        end
      end

      swagger_schema :TagCreate do
        key :required, [:type, :name]
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Tag.short_model_name.singular]
        end
        property :name do
          key :type, :string
        end
        property :relationships do
          key :"$ref", :TagCreateLinks
        end
      end

      swagger_schema :TagCreateLinks do
        property :checks do
          key :"$ref", :data_ChecksReference
        end
        property :contacts do
          key :"$ref", :data_ContactsReference
        end
        property :rules do
          key :"$ref", :data_RulesReference
        end
      end

      swagger_schema :TagUpdate do
        key :required, [:id, :type]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Tag.short_model_name.singular]
        end
        property :name do
          key :type, :string
        end
        property :relationships do
          key :"$ref", :TagUpdateLinks
        end
      end

      swagger_schema :TagUpdateLinks do
        property :checks do
          key :"$ref", :data_ChecksReference
        end
        property :contacts do
          key :"$ref", :data_ContactsReference
        end
        property :rules do
          key :"$ref", :data_RulesReference
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
            :attributes => [:name],
            :descriptions => {
              :singular => "Create a tag.",
              :multiple => "Create tags."
            }
          ),
          :get => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:name],
            :descriptions => {
              :singular => "Returns data for a tag.",
              :multiple => "Returns data for tags."
            }
          ),
          :patch => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:name],
            :descriptions => {
              :singular => "Update a tag.",
              :multiple => "Update tags."
            }
          ),
          :delete => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :descriptions => {
              :singular => "Delete a tag.",
              :multiple => "Delete tags."
            }
          )
        }
      end

      def self.jsonapi_associations
        unless instance_variable_defined?('@jsonapi_associations')
          @jsonapi_associations = {
            :checks => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :post => true, :get => true, :patch => true, :delete => true,
              :number => :multiple, :link => true, :includable => true,
              :descriptions => {
                :post => "Associate checks with this tag.",
                :get => "Returns all checks linked to this tag.",
                :patch => "Update the checks associated with this tag.",
                :delete => "Delete associations between checks and this tag."
              }
            ),
            :contacts => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :post => true, :get => true, :patch => true, :delete => true,
              :number => :multiple, :link => true, :includable => true,
              :descriptions => {
                :post => "Associate contacts with this tag.",
                :get => "Returns all contacts linked to this tag.",
                :patch => "Update the contacts associated with this tag.",
                :delete => "Delete associations between contacts and this tag."
              }
            ),
            :rules => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :post => true, :get => true, :patch => true, :delete => true,
              :number => :multiple, :link => true, :includable => true,
              :descriptions => {
                :post => "Associate rules with this tag.",
                :get => "Returns all rules linked to this tag.",
                :patch => "Update the rules associated with this tag.",
                :delete => "Delete associations between rules and this tag."
              }
            ),
            :scheduled_maintenances => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :get => true,
              :number => :multiple, :link => true, :includable => false,
              :type => 'scheduled_maintenance',
              :klass => Flapjack::Data::ScheduledMaintenance,
              :descriptions => {
                :get => "Returns all scheduled maintenance periods for " \
                        "checks linked to this tag; default sort order is " \
                        "newest first."
              }
            ),
            :states => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :get => true,
              :number => :multiple, :link => true, :includable => false,
              :type => 'state',
              :klass => Flapjack::Data::State,
              :descriptions => {
                :get => "Returns all state records for all checks linked to " \
                        "this tag; default sort order is newest first."
              }
            ),
            :unscheduled_maintenances => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :get => true,
              :number => :multiple, :link => true, :includable => false,
              :type => 'unscheduled_maintenance',
              :klass => Flapjack::Data::UnscheduledMaintenance,
              :descriptions => {
                :get => "Returns all unscheduled maintenance periods for " \
                        "checks linked to this tag; default sort order is " \
                        "newest first."
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
