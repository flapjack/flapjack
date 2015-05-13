#!/usr/bin/env ruby

module Flapjack
  module Data
    class Status

      include Zermelo::Records::Redis
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false
      include Flapjack::Gateways::JSONAPI::Data::Associations
      include Swagger::Blocks

      define_attributes :last_update          => :timestamp,
                        :last_change          => :timestamp,
                        :last_problem         => :timestamp,
                        :last_recovery        => :timestamp,
                        :last_acknowledgement => :timestamp,
                        :summary              => :string,
                        :details              => :string

      belongs_to :check, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :status

      # FIXME call these at the appropriate points
      def apply_change(entry)
        self.last_change = entry.timestamp
        apply_update(entry)
      end

      def apply_update(entry)
        self.last_update = entry.timestamp
        self.summary = entry.summary
        self.details = entry.details
      end

      def apply_notification(entry)
        if 'acknowledgement'.eql?(entry.action)
          self.last_acknowledgement = entry.timestamp
        elsif Flapjack::Data::Condition.healthy?(entry.condition)
          self.last_recovery = entry.timestamp
        else
          self.last_problem  = entry.timestamp
        end
      end

      def self.jsonapi_type
        self.name.demodulize.underscore
      end

      swagger_schema :Status do
        key :required, [:id, :last_update, :last_change, :last_problem,
                        :last_recovery, :last_acknowledgement, :summary,
                        :details]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Status.jsonapi_type.downcase]
        end
        property :last_update do
          key :type, :string
          key :format, :"date-time"
        end
        property :last_change do
          key :type, :string
          key :format, :"date-time"
        end
        property :last_problem do
          key :type, :string
          key :format, :"date-time"
        end
        property :last_recovery do
          key :type, :string
          key :format, :"date-time"
        end
        property :last_acknowledgement do
          key :type, :string
          key :format, :"date-time"
        end
        property :summary do
          key :type, :string
        end
        property :details do
          key :type, :string
        end
      end

      def self.jsonapi_methods
        [:get]
      end

      def self.jsonapi_attributes
        {
          :get => [:last_update, :last_change, :last_problem,
                   :last_recovery, :last_acknowledgement, :summary, :details]
        }
      end

      def self.jsonapi_associations
        {
          :read_only => {
            :singular => [:check],
            :multiple => []
          },
          :read_write => {
            :singular => [],
            :multiple => []
          }
        }
      end

      # # previously implemented
      # def last_update
      #   s = self.states.last
      #   return if s.nil?
      #   s.entries.last
      # end

      # def last_change
      #   s = self.states.last
      #   return if s.nil?
      #   s.entries.first
      # end

      # FIXME remove once checks/:id?include=status returns
      # equivalent data (across two objects)

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

