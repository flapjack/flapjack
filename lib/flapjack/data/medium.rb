#!/usr/bin/env ruby

require 'swagger/blocks'

require 'zermelo/records/redis'

require 'flapjack/data/extensions/short_name'
require 'flapjack/data/validators/id_validator'

require 'flapjack/data/alert'
require 'flapjack/data/check'
require 'flapjack/data/rollup'

require 'flapjack/data/extensions/associations'
require 'flapjack/gateways/jsonapi/data/join_descriptor'
require 'flapjack/gateways/jsonapi/data/method_descriptor'

module Flapjack

  module Data

    class Medium

      include Zermelo::Records::Redis
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
        'sns'
      ]

      define_attributes :transport              => :string,
                        :address                => :string,
                        :interval               => :integer,
                        :pagerduty_subdomain    => :string,
                        :pagerduty_user_name    => :string,
                        :pagerduty_password     => :string,
                        :pagerduty_token        => :string,
                        :pagerduty_ack_duration => :integer,
                        :last_rollup_type       => :string

      belongs_to :contact, :class_name => 'Flapjack::Data::Contact',
        :inverse_of => :media

      has_and_belongs_to_many :rules, :class_name => 'Flapjack::Data::Rule',
        :inverse_of => :media

      has_many :rollups, :class_name => 'Flapjack::Data::Rollup',
        :inverse_of => :medium

      # TODO minimise number of reads of this association
      has_and_belongs_to_many :alerting_checks, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :alerting_media, :before_read => :remove_checks_in_sched_maint,
        :related_class_names => ['Flapjack::Data::ScheduledMaintenance']

      # acked checks remove themselves from alerting at the time of ack, not
      # as easy to do when scheduled maintenance ticks over
      def self.remove_checks_in_sched_maint(medium_id)
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

        medium = Flapjack::Data::Medium.find_by_id!(medium_id)
        # remove_ids here (in before_read) leads to infinite callback recursion :(
        medium.alerting_checks.remove(*sched_maint_checks.all)
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

      validates_each :interval,
        :if =>  proc {|m| 'pagerduty'.eql?(m.transport) } do |record, att, value|

        record.errors.add(att, 'must be nil') unless value.nil?
      end

      validates :pagerduty_subdomain, :presence => true,
        :if => proc {|m| 'pagerduty'.eql?(m.transport) }

      validates :pagerduty_user_name, :presence => true,
        :if => proc {|m| 'pagerduty'.eql?(m.transport) && m.pagerduty_token.blank? }

      validates :pagerduty_password, :presence => true,
        :if => proc {|m| 'pagerduty'.eql?(m.transport) && m.pagerduty_token.blank? }

      validates :pagerduty_token, :presence => true,
        :if => proc {|m| 'pagerduty'.eql?(m.transport) &&
          (m.pagerduty_user_name.blank? || m.pagerduty_password.blank?) }

      validates :pagerduty_ack_duration, :allow_nil => true,
        :numericality => {:greater_than => 0, :only_integer => true},
        :if => proc {|m| 'pagerduty'.eql?(m.transport) }

      validates_each :pagerduty_subdomain, :pagerduty_user_name,
        :pagerduty_password, :pagerduty_token, :pagerduty_ack_duration,
        :unless =>  proc {|m| 'pagerduty'.eql?(m.transport) } do |record, att, value|
        record.errors.add(att, 'must be nil') unless value.nil?
      end

      validates_with Flapjack::Data::Validators::IdValidator

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
        property :pagerduty_subdomain do
          key :type, :string
        end
        property :pagerduty_user_name do
          key :type, :string
        end
        property :pagerduty_password do
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
        key :required, [:type, :address, :transport]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Medium.short_model_name.singular]
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
        property :pagerduty_subdomain do
          key :type, :string
        end
        property :pagerduty_user_name do
          key :type, :string
        end
        property :pagerduty_password do
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
        property :pagerduty_subdomain do
          key :type, :string
        end
        property :pagerduty_user_name do
          key :type, :string
        end
        property :pagerduty_password do
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
        @jsonapi_methods ||= {
          :post => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:transport, :address, :interval,
                            :pagerduty_subdomain, :pagerduty_user_name,
                            :pagerduty_password, :pagerduty_token,
                            :pagerduty_ack_duration]
          ),
          :get => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:transport, :address, :interval,
                            :pagerduty_subdomain, :pagerduty_user_name,
                            :pagerduty_password, :pagerduty_token,
                            :pagerduty_ack_duration]
          ),
          :patch => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:transport, :address, :interval,
                            :pagerduty_subdomain, :pagerduty_user_name,
                            :pagerduty_password, :pagerduty_token,
                            :pagerduty_ack_duration]
          ),
          :delete => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :lock_klasses => [Flapjack::Data::Alert, Flapjack::Data::State,
                              Flapjack::Data::Check,
                              Flapjack::Data::ScheduledMaintenance]
          )
        }
      end

      def self.jsonapi_associations
        if @jsonapi_associations.nil?
          @jsonapi_associations = {
            :alerting_checks => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :get => true,
              :number => :multiple, :link => true, :includable => true
            ),
            :contact => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :post => true, :get => true,
              :number => :singular, :link => true, :includable => true
            ),
            :rollups => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :get => true,
              :number => :multiple, :link => true, :includable => true
            ),
            :rules => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
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
