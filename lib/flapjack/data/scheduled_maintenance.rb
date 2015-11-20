#!/usr/bin/env ruby

require 'zermelo/records/redis'

require 'flapjack/data/extensions/short_name'
require 'flapjack/data/validators/id_validator'

require 'flapjack/data/extensions/associations'
require 'flapjack/gateways/jsonapi/data/join_descriptor'
require 'flapjack/gateways/jsonapi/data/method_descriptor'

module Flapjack
  module Data
    class ScheduledMaintenance
      include Zermelo::Records::RedisSortedSet
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false
      include Swagger::Blocks

      include Flapjack::Data::Extensions::Associations
      include Flapjack::Data::Extensions::ShortName

      define_attributes :start_time => :timestamp,
                        :end_time   => :timestamp,
                        :summary    => :string

      define_sort_attribute :start_time

      belongs_to :check, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :scheduled_maintenances

      def tag=(t)
        raise "Scheduled maintenance not saved" unless persisted?
        raise "Scheduled maintenance already associated" unless check.nil?

        checks = t.checks

        unless checks.empty?
          tag_checks = checks.all
          self.check = tag_checks.shift

          tag_checks.each do |ch|
            sm = Flapjack::Data::ScheduledMaintenance.new(:start_time => self.start_time,
              :end_time => end_time, :summary => summary)
            sm.save
            sm.check = ch
          end
        end
      end

      range_index_by :start_time, :end_time

      validates :start_time, :presence => true
      validates :end_time, :presence => true

      validate :positive_duration
      def positive_duration
        return if self.start_time.nil? || self.end_time.nil? ||
          (self.start_time < self.end_time)
        errors.add(:end_time, "must be greater than start time")
      end

      # # FIXME discuss whether we should let people change history
      # # I'm in favour of leaving things as flexible as possible (@ali-graham)
      # validate :times_in_future_if_changed, :on => :update
      # def times_in_future_if_changed
      #   t =  Time.now.to_i
      #   [:start_time, :end_time].each do |tf|
      #     if self.send("#{tf}_changed?".to_sym)
      #       tv = self.send(tf)
      #       if !tv.nil? && (tv < t)
      #         errors.add(tf, "cannot be changed to a time in the past")
      #       end
      #     end
      #   end
      # end

      validates_with Flapjack::Data::Validators::IdValidator

      # # FIXME discuss whether we should let people change history
      # # I'm in favour of leaving things as flexible as possible (@ali-graham)
      # before_destroy :only_destroy_future
      # def only_destroy_future
      #   (self.start_time.to_i - Time.now.to_i) > 0
      # end

      def duration
        self.end_time - self.start_time
      end

      swagger_schema :ScheduledMaintenance do
        key :required, [:id, :type, :start_time, :end_time]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::ScheduledMaintenance.short_model_name.singular]
        end
        property :start_time do
          key :type, :string
          key :format, :"date-time"
        end
        property :end_time do
          key :type, :string
          key :format, :"date-time"
        end
        property :relationships do
          key :"$ref", :ScheduledMaintenanceLinks
        end
      end

      swagger_schema :ScheduledMaintenanceLinks do
        key :required, [:check]
        property :check do
          key :"$ref", :CheckLinkage
        end
      end

      swagger_schema :ScheduledMaintenanceCreate do
        key :required, [:type, :start_time, :end_time]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::ScheduledMaintenance.short_model_name.singular]
        end
        property :start_time do
          key :type, :string
          key :format, :"date-time"
        end
        property :end_time do
          key :type, :string
          key :format, :"date-time"
        end
        property :relationships do
          key :"$ref", :ScheduledMaintenanceCreateLinks
        end
      end

      swagger_schema :ScheduledMaintenanceCreateLinks do
        key :required, [:check]
        property :check do
          key :"$ref", :data_CheckReference
        end
      end

      swagger_schema :ScheduledMaintenanceUpdate do
        key :required, [:id, :type, :start_time, :end_time]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::ScheduledMaintenance.short_model_name.singular]
        end
        property :start_time do
          key :type, :string
          key :format, :"date-time"
        end
        property :end_time do
          key :type, :string
          key :format, :"date-time"
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
            :attributes => [:start_time, :end_time, :summary],
            :descriptions => {
              :singular => "Create a scheduled maintenance period for a check, or checks associated with a tag.",
              :multiple => "Create scheduled maintenance periods for a check, or checks associated with a tag."
            }
          ),
          :get => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:start_time, :end_time, :summary],
            :descriptions => {
              :singular => "Get data for a scheduled maintenance period.",
              :multiple => "Get data for multiple scheduled maintenance periods."
            }
          ),
          :patch => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:start_time, :end_time, :summary],
            :descriptions => {
              :singular => "Update data for a scheduled maintenance period.",
              :multiple => "Update data for scheduled maintenance periods.",
            }
          ),
          :delete => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :descriptions => {
              :singular => "Delete a scheduled maintenance period.",
              :multiple => "Delete scheduled maintenance periods."
            }
          )
        }
      end

      def self.jsonapi_associations
        unless instance_variable_defined?('@jsonapi_associations')
          @jsonapi_associations = {
            :check => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :post => true, :get => true,
              :number => :singular, :link => true, :includable => true,
              :descriptions => {
                :post => "Set a check for scheduled maintenance on creation.",
                :get => "Returns the check a scheduled maintenance period applies to."
              }
            ),
            :tag => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :post => true,
              :number => :singular, :link => false, :includable => false,
              :type => 'tag',
              :klass => Flapjack::Data::Tag,
              :descriptions => {
                :post => "Set scheduled maintenance on multiple checks on creation."
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