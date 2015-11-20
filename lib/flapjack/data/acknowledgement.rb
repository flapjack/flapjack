#!/usr/bin/env ruby

require 'securerandom'

require 'active_model'
require 'swagger/blocks'

require 'zermelo/records/stub'

require 'flapjack/data/extensions/associations'
require 'flapjack/data/extensions/short_name'

require 'flapjack/data/event'

module Flapjack
  module Data
    class Acknowledgement

      include Swagger::Blocks

      include Zermelo::Records::Stub
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false

      include Flapjack::Data::Extensions::Associations
      include Flapjack::Data::Extensions::ShortName

      define_attributes :duration => :integer,
                        :summary => :string

      attr_accessor :queue

      def save!
        @id ||= SecureRandom.uuid
        @duration ||= (4 * 60 * 60)
        @saved = true
      end

      def persisted?
        !@id.nil? && @saved.is_a?(TrueClass)
      end

      def check=(c)
        raise "Acknowledgement not saved" unless persisted?
        raise "Acknowledgement queue not set" if @queue.nil? || @queue.empty?
        raise "Acknowledgement already sent" if @sent

        if c.failing && c.enabled
          @checks = [c]
          Flapjack::Data::Event.create_acknowledgements(
            @queue, @checks, :duration => self.duration, :summary => self.summary
          )
        end

        @sent = true
      end

      def tag=(t)
        raise "Acknowledgement not saved" unless persisted?
        raise "Acknowledgement queue not set" if @queue.nil? || @queue.empty?
        raise "Acknowledgement already sent" if @sent

        checks = t.checks.intersect(:failing => true, :enabled => true)

        unless checks.empty?
          @checks = checks.all
          Flapjack::Data::Event.create_acknowledgements(
            @queue, @checks, :duration => self.duration, :summary => self.summary
          )
        end

        @sent = true
      end

      swagger_schema :Acknowledgement do
        key :required, [:id, :type]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Acknowledgement.short_model_name.singular]
        end
        property :duration do
          key :type, :integer
        end
        property :summary do
          key :type, :string
        end
        property :relationships do
          key :"$ref", :AcknowledgementLinks
        end
      end

      swagger_schema :AcknowledgementLinks do
        # create (and response) must have one (and only one) of these set
        property :check do
          key :"$ref", :CheckLinkage
        end
        property :tag do
          key :"$ref", :TagLinkage
        end
      end

      swagger_schema :AcknowledgementCreate do
        key :required, [:type]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Acknowledgement.short_model_name.singular]
        end
        property :duration do
          key :type, :integer
        end
        property :summary do
          key :type, :string
        end
        property :relationships do
          key :"$ref", :AcknowledgementCreateLinks
        end
      end

      swagger_schema :AcknowledgementCreateLinks do
        # create (and response) must have one (and only one) of these set
        # key :required, [:check, :tag]
        property :check do
          key :"$ref", :data_CheckReference
        end
        property :tag do
          key :"$ref", :data_TagReference
        end
      end

      def self.swagger_included_classes
        # hack -- hardcoding for now
        []
      end

      def self.jsonapi_methods
        @jsonapi_methods ||= {
          :post => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:duration, :summary],
            :descriptions => {
              :singular => "Acknowledge a check, or acknowledge all checks linked to a tag.",
              :multiple => "Acknowledge multiple checks, or checks linked to different tags."
            }
          )
        }
      end

      def self.jsonapi_associations
        unless instance_variable_defined?('@jsonapi_associations')
          @jsonapi_associations = {
            :check => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :post => true,
              :number => :singular, :link => false, :includable => false,
              :type => 'check',
              :klass => Flapjack::Data::Check
            ),
            :tag => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :post => true,
              :number => :singular, :link => false, :includable => false,
              :type => 'tag',
              :klass => Flapjack::Data::Tag
            )
          }
          populate_association_data(@jsonapi_associations)
        end
        @jsonapi_associations
      end
    end
  end
end
