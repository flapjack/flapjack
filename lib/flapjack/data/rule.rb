#!/usr/bin/env ruby

require 'set'

require 'ice_cube'
require 'swagger/blocks'

require 'zermelo/records/redis'

require 'flapjack/data/extensions/short_name'
require 'flapjack/data/validators/id_validator'

require 'flapjack/data/route'
require 'flapjack/data/time_restriction'

require 'flapjack/data/extensions/associations'
require 'flapjack/data/extensions/rule_matcher'
require 'flapjack/gateways/jsonapi/data/join_descriptor'
require 'flapjack/gateways/jsonapi/data/method_descriptor'

module Flapjack
  module Data
    class Rule

      extend Flapjack::Utility

      include Zermelo::Records::Redis
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false
      include Swagger::Blocks

      include Flapjack::Data::Extensions::Associations
      include Flapjack::Data::Extensions::RuleMatcher
      include Flapjack::Data::Extensions::ShortName

      belongs_to :contact, :class_name => 'Flapjack::Data::Contact',
        :inverse_of => :rules

      has_and_belongs_to_many :media, :class_name => 'Flapjack::Data::Medium',
        :inverse_of => :rules, :after_add => :has_some_media,
        :after_remove => :has_no_media

      has_and_belongs_to_many :tags, :class_name => 'Flapjack::Data::Tag',
        :inverse_of => :rules, :after_add => :tags_added,
        :after_remove => :tags_removed,
        :related_class_names => ['Flapjack::Data::Contact',
          'Flapjack::Data::Check', 'Flapjack::Data::Route']

      def self.tags_added(rule_id, *t_ids)
        rule = Flapjack::Data::Rule.find_by_id!(rule_id)
        rule.has_tags = true
        rule.recalculate_routes
        rule.save!
      end

      def self.tags_removed(rule_id, *t_ids)
        rule = Flapjack::Data::Rule.find_by_id!(rule_id)
        rule.has_tags = rule.tags.empty?
        rule.recalculate_routes
        rule.save!
      end

      has_many :routes, :class_name => 'Flapjack::Data::Route',
        :inverse_of => :rule

      before_destroy :remove_routes
      def remove_routes
        self.routes.destroy_all
      end

      # NB when a rule is created, recalculate_routes should be called
      # by the creating code if no tags are being added. FIXME -- maybe do
      # from an after_create hook just to be safe?
      #
      # FIXME on change to conditions_list, update value for all routes
      def recalculate_routes
        self.routes.destroy_all
        return unless self.has_tags

        co = self.contact
        contact_id = co.nil? ? nil : co.id

        check_assocs = self.tags.associations_for(:checks).values
        return if check_assocs.empty?

        checks = check_assocs.inject(Flapjack::Data::Check) do |memo, ca|
          memo = memo.intersect(:id => ca)
          memo
        end

        checks.each do |check|
          route = Flapjack::Data::Route.new(:alertable => false,
            :conditions_list => self.conditions_list)
          route.save

          self.routes << route
          check.routes << route
          check.contacts.add_ids(contact_id) unless contact_id.nil?
        end
      end

      swagger_schema :Rule do
        key :required, [:id, :type]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Rule.short_model_name.singular]
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
          key :"$ref", :RuleLinks
        end
      end

      swagger_schema :RuleLinks do
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

      swagger_schema :RuleCreate do
        key :required, [:type]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Rule.short_model_name.singular]
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
          key :"$ref", :RuleChangeLinks
        end
      end

      swagger_schema :RuleUpdate do
        key :required, [:id, :type]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Rule.short_model_name.singular]
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
          key :"$ref", :RuleChangeLinks
        end
      end

      swagger_schema :RuleChangeLinks do
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
            :lock_klasses => [Flapjack::Data::Contact, Flapjack::Data::Medium,
                              Flapjack::Data::Tag, Flapjack::Data::Check,
                              Flapjack::Data::Route]
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

