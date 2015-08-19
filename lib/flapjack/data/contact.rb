#!/usr/bin/env ruby

# NB: use of redis.keys probably indicates we should maintain a data
# structure to avoid the need for this type of query

require 'securerandom'
require 'set'

require 'ice_cube'
require 'swagger/blocks'

require 'zermelo/records/redis'

require 'flapjack/data/extensions/short_name'
require 'flapjack/data/validators/id_validator'

require 'flapjack/data/acceptor'
require 'flapjack/data/medium'
require 'flapjack/data/rejector'
require 'flapjack/data/tag'

require 'flapjack/data/extensions/associations'
require 'flapjack/gateways/jsonapi/data/join_descriptor'
require 'flapjack/gateways/jsonapi/data/method_descriptor'

module Flapjack

  module Data

    class Contact

      include Zermelo::Records::Redis
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false
      include Swagger::Blocks

      include Flapjack::Data::Extensions::Associations
      include Flapjack::Data::Extensions::ShortName

      define_attributes :name     => :string,
                        :timezone => :string

      index_by :name

      has_many :acceptors, :class_name => 'Flapjack::Data::Acceptor',
        :inverse_of => :contact

      has_many :rejectors, :class_name => 'Flapjack::Data::Rejector',
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
        self.acceptors.each  {|acceptor| acceptor.destroy }
        self.media.each      {|medium|   medium.destroy }
        self.rejectors.each  {|rejector| rejector.destroy }
      end

      def time_zone
        return nil if self.timezone.nil?
        ActiveSupport::TimeZone[self.timezone]
      end

      def checks
        tag_acceptors    = self.acceptors.intersect(:all => [nil, false])
        global_acceptors = self.acceptors.intersect(:all => true)

        tag_rejectors    = self.rejectors.intersect(:all => [nil, false])

        global_rejector_ids = self.rejectors.intersect(:all => true).select {|rejector|
          rejector.is_occurring_at?(time, timezone)
        }.map(&:id)

        # global blackhole
        return Flapjack::Data::Check.empty unless global_rejector_ids.empty?

        rejector_ids = self.rejectors.intersect(:all => [nil, false]).select {|rejector|
          rejector.is_occurring_at?(time, timezone)
        }.map(&:id)

        acceptors = self.acceptors.select {|acceptor|
          acceptor.is_occurring_at?(time, timezone)
        }

        # no positives
        return Flapjack::Data::Check.empty if acceptors.empty?


        # initial scope is all enabled
        linked_checks = Flapjack::Data::Check.intersect(:enabled => true)

        if acceptors.none? {|a| a.all }
          # if no global acceptor, scope by matching tags
          acceptor_checks = Flapjack::Data::Acceptor.matching_checks(acceptors.map(&:id))
          linked_checks = linked_checks.intersect(:id => acceptor_checks)
        end

        # then exclude by checks with tags matching rejector, if any
        rejector_checks = Flapjack::Data::Rejector.matching_checks(rejector_ids)
        unless rejector_checks.empty?
          linked_checks = linked_checks.diff(:id => rejector_checks)
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
        key :required, [:self, :checks, :media, :rules]
        property :self do
          key :type, :string
          key :format, :url
        end
        property :acceptors do
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
        property :rejectors do
          key :type, :string
          key :format, :url
        end
        property :tags do
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
          key :"$ref", :ContactChangeLinks
        end
      end

      swagger_schema :ContactChangeLinks do
        property :acceptors do
          key :"$ref", :jsonapi_AcceptorsLinkage
        end
        property :media do
          key :"$ref", :jsonapi_MediaLinkage
        end
        property :rejectors do
          key :"$ref", :jsonapi_RejectorsLinkage
        end
        property :tags do
          key :"$ref", :jsonapi_TagsLinkage
        end
      end

      def self.jsonapi_methods
        @jsonapi_methods ||= {
          :post => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:name, :timezone]
          ),
          :get => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:name, :timezone]
          ),
          :patch => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:name, :timezone]
          ),
          :delete => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
          ),
        }
      end

      def self.jsonapi_associations
        if @jsonapi_associations.nil?
          @jsonapi_associations = {
            :acceptors => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :get => true,
              :number => :multiple, :link => true, :includable => true
            ),
            :checks => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :get => true,
              :number => :multiple, :link => true, :includable => true,
              :type => 'check',
              :klass => Flapjack::Data::Check
            ),
            :media => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :get => true,
              :number => :multiple, :link => true, :includable => true
            ),
            :rejectors => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :get => true,
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
