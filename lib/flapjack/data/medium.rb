#!/usr/bin/env ruby

require 'swagger/blocks'

require 'zermelo/records/redis'

require 'flapjack/data/validators/id_validator'

require 'flapjack/data/alert'
require 'flapjack/data/check'

require 'flapjack/gateways/jsonapi/data/associations'

module Flapjack

  module Data

    class Medium

      include Zermelo::Records::Redis
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false
      include Flapjack::Gateways::JSONAPI::Data::Associations
      include Swagger::Blocks

      TRANSPORTS = ['email', 'sms', 'jabber', 'pagerduty', 'sns', 'sms_twilio']

      define_attributes :transport              => :string,
                        :address                => :string,
                        :interval               => :integer,
                        :rollup_threshold       => :integer,
                        :pagerduty_subdomain    => :string,
                        :pagerduty_token        => :string,
                        :pagerduty_ack_duration => :integer,
                        :last_rollup_type       => :string

      belongs_to :contact, :class_name => 'Flapjack::Data::Contact',
        :inverse_of => :media

      has_and_belongs_to_many :rules, :class_name => 'Flapjack::Data::Rule',
        :inverse_of => :media

      has_and_belongs_to_many :alerting_checks, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :alerting_media, :before_read => :remove_checks_in_sched_maint,
        :related_class_names => ['Flapjack::Data::ScheduledMaintenance']

      has_many :alerts, :class_name => 'Flapjack::Data::Alert', :inverse_of => :medium

      belongs_to :last_entry, :class_name => 'Flapjack::Data::Entry',
        :inverse_of => :latest_media

      index_by :transport

      validates :transport, :presence => true,
        :inclusion => {:in => Flapjack::Data::Medium::TRANSPORTS }

      validates :address, :presence => true

      validates :interval, :presence => true,
        :numericality => {:greater_than_or_equal_to => 0, :only_integer => true},
        :unless => proc {|m| 'pagerduty'.eql?(m.transport) }

      validates :rollup_threshold, :allow_nil => true,
        :numericality => {:greater_than => 0, :only_integer => true},
        :unless => proc {|m| 'pagerduty'.eql?(m.transport) }

      validates_each :interval, :rollup_threshold,
        :if =>  proc {|m| 'pagerduty'.eql?(m.transport) } do |record, att, value|

        record.errors.add(att, 'must be nil') unless value.nil?
      end

      validates :pagerduty_subdomain, :presence => true,
        :if => proc {|m| 'pagerduty'.eql?(m.transport) }

      validates :pagerduty_token, :presence => true,
        :if => proc {|m| 'pagerduty'.eql?(m.transport) }

      validates :pagerduty_ack_duration, :allow_nil => true,
        :numericality => {:greater_than => 0, :only_integer => true},
        :if => proc {|m| 'pagerduty'.eql?(m.transport) }

      validates_each :pagerduty_subdomain, :pagerduty_token, :pagerduty_ack_duration,
        :unless =>  proc {|m| 'pagerduty'.eql?(m.transport) } do |record, att, value|
        record.errors.add(att, 'must be nil') unless value.nil?
      end

      validates_with Flapjack::Data::Validators::IdValidator

      # TODO before_read/after_read association callbacks in zermelo
      # dynamically update alerting checks as a proper association, map it in
      # the API/swagger

      # def alerting_checks
      #   route_ids_by_rule_id = self.rules.associated_ids_for(:routes)
      #   route_ids = route_ids_by_rule_id.values.reduce(&:|)

      #   check_ids = Flapjack::Data::Route.intersect(:id => route_ids,
      #     :is_alerting => true).associated_ids_for(:checks).values.reduce(:|)

      #   time = Time.now

      #   # scheduled maintenance may have occurred without the routes being updated
      #   Flapjack::Data::Check.intersect(:id => check_ids).select do |check|
      #     !check.in_scheduled_maintenance?(time)
      #   end
      # end

      # acked checks remove themselves from alerting at the time of ack, not
      # as easy to do when scheduled maintenance ticks over
      def remove_checks_in_sched_maint
        time = Time.now

        start_range = Zermelo::Filters::IndexRange.new(nil, time, :by_score => true)
        end_range   = Zermelo::Filters::IndexRange.new(time, nil, :by_score => true)

        check_ids_by_sched_maint_ids = Flapjack::Data::ScheduledMaintenance.
          intersect(:start_time => start_range, :end_time => end_range).
          associated_ids_for(:check)

        sched_maint_check_ids = Set.new(check_ids_by_sched_maint_ids.values.flatten(1))

        return if sched_maint_check_ids.empty?

        sched_maint_checks = Flapjack::Data::Check.intersect(:id => sched_maint_check_ids)
        return if sched_maint_checks.empty?

        self.alerting_checks.delete(*sched_maint_checks.all)
      end

      def self.jsonapi_type
        self.name.demodulize.underscore
      end

      swagger_schema :Medium do
        key :required, [:id, :type, :transport]

        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Medium.jsonapi_type.downcase]
        end
        property :transport do
          key :type, :string
          key :enum, Flapjack::Data::Medium::TRANSPORTS.map(&:to_sym)
        end
        property :address do
          key :type, :string
        end
        property :interval do
          key :type, :integer
          key :minimum, 0
        end
        property :rollup_threshold do
          key :type, :integer
          key :minimum, 1
        end
        property :pagerduty_subdomain do
          key :type, :string
        end
        property :pagerduty_token do
          key :type, :string
        end
        property :pagerduty_ack_duration do
          key :type, :integer
          key :minimum, 1
        end
        property :links do
          key :"$ref", :MediumLinks
        end
      end

      swagger_schema :MediumLinks do
        key :required, [:self, :contact, :rules]
        property :self do
          key :type, :string
          key :format, :url
        end
        property :contact do
          key :type, :string
          key :format, :url
        end
        property :rules do
          key :type, :string
          key :format, :url
        end
      end

      swagger_schema :MediumCreate do
        # would require interval & rollup_threshold, but pagerduty :(
        # TODO fix when userdata added
        key :required, [:type, :address, :transport]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Medium.jsonapi_type.downcase]
        end
        property :name do
          key :type, :string
        end
        property :transport do
          key :type, :string
          key :enum, Flapjack::Data::Medium::TRANSPORTS.map(&:to_sym)
        end
        property :address do
          key :type, :string
        end
        property :interval do
          key :type, :integer
          key :minimum, 0
        end
        property :rollup_threshold do
          key :type, :integer
          key :minimum, 1
        end
        property :pagerduty_subdomain do
          key :type, :string
        end
        property :pagerduty_token do
          key :type, :string
        end
        property :pagerduty_ack_duration do
          key :type, :integer
          key :minimum, 1
        end
        property :links do
          key :"$ref", :MediumChangeLinks
        end
      end

      swagger_schema :MediumUpdate do
        key :required, [:id, :type]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Medium.jsonapi_type.downcase]
        end
        property :transport do
          key :type, :string
          key :enum, Flapjack::Data::Medium::TRANSPORTS.map(&:to_sym)
        end
        property :address do
          key :type, :string
        end
        property :interval do
          key :type, :integer
          key :minimum, 0
        end
        property :rollup_threshold do
          key :type, :integer
          key :minimum, 1
        end
        property :pagerduty_subdomain do
          key :type, :string
        end
        property :pagerduty_token do
          key :type, :string
        end
        property :pagerduty_ack_duration do
          key :type, :integer
          key :minimum, 1
        end
        property :links do
          key :"$ref", :MediumChangeLinks
        end
      end

      swagger_schema :MediumChangeLinks do
        property :contact do
          key :"$ref", :jsonapi_ContactLinkage
        end
        property :rules do
          key :"$ref", :jsonapi_RulesLinkage
        end
      end

      def self.jsonapi_methods
        [:post, :get, :patch, :delete]
      end

      def self.jsonapi_attributes
        {
          :post  => [:transport, :address, :interval, :rollup_threshold,
                     :pagerduty_subdomain, :pagerduty_token, :pagerduty_ack_duration],
          :get   => [:transport, :address, :interval, :rollup_threshold,
                     :pagerduty_subdomain, :pagerduty_token, :pagerduty_ack_duration],
          :patch => [:transport, :address, :interval, :rollup_threshold,
                     :pagerduty_subdomain, :pagerduty_token, :pagerduty_ack_duration]
        }
      end

      def self.jsonapi_extra_locks
        {
          :post   => [],
          :get    => [],
          :patch  => [],
          :delete => [Flapjack::Data::Alert, Flapjack::Data::Entry,
                      Flapjack::Data::Check, Flapjack::Data::ScheduledMaintenance]
        }
      end

      def self.jsonapi_associations
        {
          :read_only => {
            :singular => [],
            :multiple => [:alerting_checks]
          },
          :read_write => {
            :singular => [:contact],
            :multiple => [:rules]
          }
        }
      end
    end
  end
end
