#!/usr/bin/env ruby

require 'swagger/blocks'

require 'zermelo/records/redis'

require 'flapjack/data/extensions/short_name'
require 'flapjack/data/validators/id_validator'

require 'flapjack/data/condition'

require 'flapjack/data/extensions/associations'
require 'flapjack/gateways/jsonapi/data/join_descriptor'
require 'flapjack/gateways/jsonapi/data/method_descriptor'

module Flapjack
  module Data
    class State

      include Zermelo::Records::RedisSortedSet
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false
      include Swagger::Blocks

      include Flapjack::Data::Extensions::Associations
      include Flapjack::Data::Extensions::ShortName

      define_attributes :created_at    => :timestamp,
                        :updated_at    => :timestamp,
                        :condition     => :string,
                        :action        => :string,
                        :summary       => :string,
                        :details       => :string,
                        :perfdata_json => :string

      define_sort_attribute :created_at

      index_by :condition, :action
      range_index_by :created_at

      # public
      belongs_to :check, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :states

      # private

      # these 'Check' values will be the same as the above, but zermelo
      # requires that the inverse of the association be stored as well
      belongs_to :current_check, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :current_state

      belongs_to :latest_notifications_check, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :latest_notifications

      belongs_to :most_severe_check, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :most_severe

      belongs_to :notification, :class_name => 'Flapjack::Data::Notification',
        :inverse_of => :state

      has_many :latest_media, :class_name => 'Flapjack::Data::Medium',
        :inverse_of => :last_state

      validates :created_at, :presence => true
      validates :updated_at, :presence => true

      # condition should only be blank if no previous entry with condition for check
      validates :condition, :allow_blank => true,
        :inclusion => { :in => Flapjack::Data::Condition.healthy.keys +
                               Flapjack::Data::Condition.unhealthy.keys }

      ACTIONS = %w(acknowledgement test_notifications)
      validates :action, :allow_nil => true,
        :format => {:with => /\A(?:acknowledgement|test_notifications(\s+#{Flapjack::Data::Condition.unhealthy.keys.join('|')})?)\z/,
        :message => 'must either be an acknowledgement or a notification test'}

      # TODO handle JSON exception
      def perfdata
        if self.perfdata_json.nil?
          @perfdata = nil
          return
        end
        @perfdata ||= Flapjack.load_json(self.perfdata_json)
      end

      # example perfdata: time=0.486630s;;;0.000000 size=909B;;;0
      def perfdata=(data)
        if data.nil?
          self.perfdata_json = nil
          return
        end

        data = data.strip
        if data.length == 0
          self.perfdata_json = nil
          return
        end
        # Could maybe be replaced by a fancy regex
        @perfdata = data.split(' ').inject([]) do |item|
          parts = item.split('=')
          memo << {"key"   => parts[0].to_s,
                   "value" => parts[1].nil? ? '' : parts[1].split(';')[0].to_s}
          memo
        end
        self.perfdata_json = @perfdata.nil? ? nil : Flapjack.dump_json(@perfdata)
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

      swagger_schema :State do
        key :required, [:id, :created_at, :updated_at, :condition, :action,
                        :summary, :details, :perfdata]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::State.short_model_name.singular]
        end
        property :created_at do
          key :type, :string
          key :format, :"date-time"
        end
        property :updated_at do
          key :type, :string
          key :format, :"date-time"
        end
        property :condition do
          key :type, :string
          key :enum, Flapjack::Data::Condition.healthy.keys +
                       Flapjack::Data::Condition.unhealthy.keys
        end
        property :action do
          key :type, :string
          key :enum, Flapjack::Data::State::ACTIONS
        end
        property :summary do
          key :type, :string
        end
        property :details do
          key :type, :string
        end
        property :perfdata do
          key :type, :string
        end
        property :relationships do
          key :"$ref", :StateLinks
        end
      end

      swagger_schema :StateLinks do
        key :required, [:check]
        property :check do
          key :"$ref", :CheckLinkage
        end
      end

      def self.jsonapi_methods
        @jsonapi_methods ||= {
          :get => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:created_at, :updated_at, :condition, :action,
                            :summary, :details, :perfdata],
            :descriptions => {
              :singular => "Get data for a single check state record.",
              :multiple => "Get data for check state records."
            }
          )
        }
      end

      def self.jsonapi_associations
        unless instance_variable_defined?('@jsonapi_associations')
          @jsonapi_associations = {
            :check => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :get => true,
              :number => :singular, :link => true, :includable => true,
              :descriptions => {
                :get => "Returns the check the state data describes."
              }
            )
          }
          populate_association_data(@jsonapi_associations)
        end
        @jsonapi_associations
      end

      before_destroy :is_unlinked

      def is_unlinked
        Flapjack.logger.debug "checking deletion of #{self.instance_variable_get('@attributes').inspect}"
        Flapjack.logger.debug "check #{self.check.nil?}"
        Flapjack.logger.debug "latest_notifications_check nil #{self.latest_notifications_check.nil?}"
        Flapjack.logger.debug "most_severe_check nil #{self.most_severe_check.nil?}"
        Flapjack.logger.debug "notification nil #{self.notification.nil?}"
        Flapjack.logger.debug "latest media empty #{self.latest_media.empty?}"

        return false unless self.check.nil? &&
          self.latest_notifications_check.nil? && self.most_severe_check.nil? &&
          self.notification.nil? && self.latest_media.empty?

        Flapjack.logger.debug "deleting"

        true
      end
    end
  end
end

