#!/usr/bin/env ruby

require 'swagger/blocks'

require 'zermelo/records/redis'

require 'flapjack/data/alert'
require 'flapjack/data/check'
require 'flapjack/data/contact'
require 'flapjack/data/rule'
require 'flapjack/data/scheduled_maintenance'
require 'flapjack/data/unscheduled_maintenance'

require 'flapjack/data/extensions/associations'
require 'flapjack/data/extensions/short_name'
require 'flapjack/data/validators/id_validator'

require 'flapjack/gateways/jsonapi/data/join_descriptor'
require 'flapjack/gateways/jsonapi/data/method_descriptor'

module Flapjack

  module Data

    class Medium

      include Zermelo::Records::RedisSet
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false
      include Swagger::Blocks

      include Flapjack::Data::Extensions::Associations
      include Flapjack::Data::Extensions::ShortName

      TRANSPORTS = [
        'email',
        'jabber',
        'pagerduty',
        'sms',
        'slack',
        'sms_twilio',
        'sms_nexmo',
      	'sms_aspsms',
        'sns'
      ]

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

      # this can be called from the API (with no args) or from notifier.rb
      # (which will pass an effective time)
      def alerting_checks(opts = {})
        time = opts[:time] || Time.now
        init_scope = Flapjack::Data::Check.intersect(:enabled => true, :alertable => true)
        ret = checks(:initial_scope => init_scope,
                     :time => Time.now)

        return Flapjack::Data::Check.empty if ret.empty?

        start_range = Zermelo::Filters::IndexRange.new(nil, time, :by_score => true)
        end_range   = Zermelo::Filters::IndexRange.new(time, nil, :by_score => true)

        sched_maint_check_ids = Flapjack::Data::ScheduledMaintenance.
          intersect(:start_time => start_range, :end_time => end_range).
          associated_ids_for(:check).values

        ret = ret.diff(:id => sched_maint_check_ids) unless sched_maint_check_ids.empty?

        unsched_maint_check_ids = Flapjack::Data::UnscheduledMaintenance.
          intersect(:start_time => start_range, :end_time => end_range).
          associated_ids_for(:check).values

        ret = ret.diff(:id => unsched_maint_check_ids) unless unsched_maint_check_ids.empty?
        ret
      end

      def checks(opts = {})
        time_zone = self.contact.time_zone
        time = opts[:time] || Time.now
        init_scope = opts[:initial_scope] || Flapjack::Data::Check.intersect(:enabled => true)

        # TODO maybe fold time validation into 'matching_checks'
        global_rejector_ids = self.rules.intersect(:enabled => true, :blackhole => true,
          :strategy => 'global').select {|rejector|

          rejector.is_occurring_at?(time, time_zone)
        }.map(&:id)

        unless global_rejector_ids.empty?
          # global blackhole
          return Flapjack::Data::Check.empty
        end

        rejector_ids = self.rules.intersect(:enabled => true, :blackhole => true,
          :strategy => ['all_tags', 'any_tag', 'no_tag']).select {|rejector|

          rejector.is_occurring_at?(time, time_zone)
        }.map(&:id)

        acceptors = self.rules.intersect(:enabled => true, :blackhole => false).select {|acceptor|
          acceptor.is_occurring_at?(time, time_zone)
        }

        # no positives
        return Flapjack::Data::Check.empty if acceptors.empty?

        ret = init_scope

        if acceptors.none? {|a| 'global'.eql?(a.strategy) }
          # if no global acceptor, scope by tags for acceptors
          acceptor_checks = Flapjack::Data::Rule.matching_checks(acceptors.map(&:id))
          ret = ret.intersect(:id => acceptor_checks)
        end

        # then exclude by checks with tags matching rejector, if any
        rejector_checks = Flapjack::Data::Rule.matching_checks(rejector_ids)
        unless rejector_checks.empty?
          ret = ret.diff(:id => rejector_checks)
        end

        ret
      end

      has_many :alerts, :class_name => 'Flapjack::Data::Alert', :inverse_of => :medium

      belongs_to :last_state, :class_name => 'Flapjack::Data::State',
        :inverse_of => :latest_media, :after_clear => :destroy_state

      def self.destroy_state(medium_id, st_id)
        # won't be deleted if still referenced elsewhere -- see the State
        # before_destroy callback
        Flapjack::Data::State.intersect(:id => st_id).destroy_all
      end

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

      validates_each :pagerduty_subdomain, :pagerduty_token,
        :pagerduty_ack_duration,
        :unless =>  proc {|m| 'pagerduty'.eql?(m.transport) } do |record, att, value|
        record.errors.add(att, 'must be nil') unless value.nil?
      end

      validates_with Flapjack::Data::Validators::IdValidator

      swagger_schema :Medium do
        key :required, [:id, :type, :transport]

        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Medium.short_model_name.singular]
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
        property :relationships do
          key :"$ref", :MediumLinks
        end
      end

      swagger_schema :MediumLinks do
        key :required, [:contact, :rules]
        property :contact do
          key :"$ref", :ContactLinkage
        end
        property :rules do
          key :"$ref", :RulesLinkage
        end
      end

      swagger_schema :MediumCreate do
        key :required, [:type, :address, :transport]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Medium.short_model_name.singular]
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
        property :relationships do
          key :"$ref", :MediumCreateLinks
        end
      end

      swagger_schema :MediumCreateLinks do
        key :required, [:contact]
        property :contact do
          key :"$ref", :data_ContactReference
        end
        property :rules do
          key :"$ref", :data_RulesReference
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
          key :enum, [Flapjack::Data::Medium.short_model_name.singular]
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
        property :relationships do
          key :"$ref", :MediumUpdateLinks
        end
      end

      swagger_schema :MediumUpdateLinks do
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
            :attributes => [:transport, :address, :interval, :rollup_threshold,
                            :pagerduty_subdomain, :pagerduty_token,
                            :pagerduty_ack_duration],
            :descriptions => {
              :singular => "Create a media record.",
              :multiple => "Create media records."
            }
          ),
          :get => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:transport, :address, :interval, :rollup_threshold,
                            :pagerduty_subdomain, :pagerduty_token,
                            :pagerduty_ack_duration],
            :descriptions => {
              :singular => "Returns data for a media record.",
              :multiple => "Returns data for media records."
            }
          ),
          :patch => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:transport, :address, :interval, :rollup_threshold,
                            :pagerduty_subdomain, :pagerduty_token,
                            :pagerduty_ack_duration],
            :descriptions => {
              :singular => "Update a media record.",
              :multiple => "Update media records."
            }
          ),
          :delete => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :descriptions => {
              :singular => "Delete a media record.",
              :multiple => "Delete media records."
            }
          )
        }
      end

      def self.jsonapi_associations
        unless instance_variable_defined?('@jsonapi_associations')
          @jsonapi_associations = {
            :alerting_checks => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :get => true,
              :number => :multiple, :link => true, :includable => true,
              :type => 'check',
              :klass => Flapjack::Data::Check,
              :callback_classes => [
                Flapjack::Data::Contact,
                Flapjack::Data::Rule,
                Flapjack::Data::ScheduledMaintenance
              ],
              :descriptions => {
                :get => "Returns all checks that have alerted through a medium (that are still failing."
              }
            ),
            :contact => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :post => true, :get => true,
              :number => :singular, :link => true, :includable => true,
              :descriptions => {
                :post => "Set a contact for a medium during medium creation (required).",
                :get => "Get the contact a medium belongs to."
              }
            ),
            :rules => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :post => true, :get => true, :patch => true, :delete => true,
              :number => :multiple, :link => true, :includable => true,
              :descriptions => {
                :post => "Associate this medium with rules on medium creation.",
                :get => "Get the rules this medium is associated with.",
                :patch => "Update the rules this medium is associated with.",
                :delete => "Delete associations between this medium and rules."
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
