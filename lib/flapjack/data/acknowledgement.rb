#!/usr/bin/env ruby

require 'swagger/blocks'

require 'zermelo/records/redis'

require 'flapjack/data/validators/id_validator'

require 'flapjack/gateways/jsonapi/data/associations'
require 'flapjack/gateways/jsonapi/data/join_descriptor'
require 'flapjack/gateways/jsonapi/data/method_descriptor'

module Flapjack
  module Data
    class Acknowledgement

      include Swagger::Blocks

      attr_accessor :type, :check_name, :start_time, :duration, :summary

      # FIXME trigger on "save"
      def trigger_ack_event
        Flapjack::Data::Check.intersect(:name => check_name).each do |check|

        end
      end

      def self.jsonapi_type
        self.name.demodulize.underscore
      end

      swagger_schema :AcknowledgementCreate do
        key :required, [:type, :check_name, :start_time, :duration]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Acknowledgement.jsonapi_type.downcase]
        end
        property :check_name do
          key :type, :string
        end
        property :start_time do
          key :type, :string
          key :format, :"date-time"
        end
        property :duration do
          key :type, :integer
        end
        property :summary do
          key :type, :string
        end
      end

      def self.jsonapi_methods
        @jsonapi_methods ||= {
          :post => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:start_time, :duration, :summary, :check_name]
          )
        }
      end

      def self.jsonapi_associations
        @jsonapi_associations ||= {}
      end

      private

      def ensure_start_time
        self.start_time ||= Time.now
      end

    end
  end
end
