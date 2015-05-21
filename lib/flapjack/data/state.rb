#!/usr/bin/env ruby

# the name represents a 'log entry', as Flapjack's data model resembles an
# audit log.

# TODO when removed from an associated check or notification, if the rest of
# those associations are not present, remove it from the state's associations
# and delete it

require 'swagger/blocks'

require 'zermelo/records/redis'

require 'flapjack/data/condition'
require 'flapjack/data/notification'

require 'flapjack/data/validators/id_validator'

require 'flapjack/gateways/jsonapi/data/associations'

module Flapjack
  module Data
    class State

      include Zermelo::Records::Redis
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false
      include Flapjack::Gateways::JSONAPI::Data::Associations
      include Swagger::Blocks

      define_attributes :created_at        => :timestamp,
                        :updated_at        => :timestamp,
                        :condition         => :string,
                        :action            => :string,
                        :summary           => :string,
                        :details           => :string,
                        :perfdata_json     => :string

      index_by :condition, :action
      range_index_by :created_at, :updated_at

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
        :inclusion => {:in => Flapjack::Data::State::ACTIONS}

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

      def self.jsonapi_type
        self.name.demodulize.underscore
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
          key :enum, [Flapjack::Data::State.jsonapi_type.downcase]
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
        property :links do
          key :"$ref", :StateLinks
        end
      end

      swagger_schema :StateLinks do
        key :required, [:self]
        property :self do
          key :type, :string
          key :format, :url
        end
        property :check do
          key :type, :string
          key :format, :url
        end
      end

      def self.jsonapi_methods
        [:get]
      end

      def self.jsonapi_attributes
        {
          :get => [:created_at, :updated_at, :condition, :action, :summary,
                   :details, :perfdata]
        }
      end

      def self.jsonapi_extra_locks
        {
          :get    => []
        }
      end

      # read-only by definition; singular & multiple hashes of
      # method_name => [other classes to lock]
      def self.jsonapi_linked_methods
        {
          :singular => {
          },
          :multiple => {
          }
        }
      end

      def self.jsonapi_associations
        {
          :read_only => {
            :singular => [:check],
            :multiple => []
          }
        }
      end

      # FIXME ensure state.destroy is called when removed from:
      # latest_notifications
      # most_severe
      # notification
      # latest_media
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

        return true
      end

      # # previously implemented
      # def status
        # last_change   = @check.last_change
        # last_update   = @check.last_update
        # last_problem  = @check.latest_notifications.
        #   intersect(:condition => Flapjack::Data::Condition.unhealthy.keys).first
        # last_recovery = @check.latest_notifications.
        #   intersect(:condition => Flapjack::Data::Condition.healthy.keys).first
        # last_ack      = @check.latest_notifications.
        #   intersect(:action => 'acknowledgement').first

        # {'name'                              => @check.name,
        #  'condition'                         => @check.condition,
        #  'enabled'                           => @check.enabled,
        #  'summary'                           => @check.summary,
        #  'details'                           => @check.details,
        #  'in_unscheduled_maintenance'        => @check.in_unscheduled_maintenance?,
        #  'in_scheduled_maintenance'          => @check.in_scheduled_maintenance?,
        #  'initial_failure_delay'             => @check.initial_failure_delay,
        #  'repeat_failure_delay'              => @check.repeat_failure_delay,
        #  'last_update'                       => last_update,
        #  'last_change'                       => last_change   ? last_change.timestamp   : nil),
        #  'last_problem_notification'         => (last_problem  ? last_problem.timestamp  : nil),
        #  'last_recovery_notification'        => (last_recovery ? last_recovery.timestamp : nil),
        #  'last_acknowledgement_notification' => (last_ack      ? last_ack.timestamp      : nil),
        # }
      # end

    end
  end
end

