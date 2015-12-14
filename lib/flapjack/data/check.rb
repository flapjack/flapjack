#!/usr/bin/env ruby

require 'digest'

require 'swagger/blocks'

require 'zermelo/records/redis'

require 'flapjack/data/extensions/short_name'
require 'flapjack/data/validators/id_validator'

require 'flapjack/data/condition'
require 'flapjack/data/state'
require 'flapjack/data/unscheduled_maintenance'

require 'flapjack/data/extensions/associations'
require 'flapjack/data/extensions/short_name'

require 'flapjack/gateways/jsonapi/data/join_descriptor'
require 'flapjack/gateways/jsonapi/data/method_descriptor'

module Flapjack
  module Data
    class Check

      include Zermelo::Records::RedisSet
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false
      include Swagger::Blocks

      include Flapjack::Data::Extensions::Associations
      include Flapjack::Data::Extensions::ShortName

      define_attributes :name                   => :string,
                        :enabled                => :boolean,
                        :initial_failure_delay  => :integer,
                        :repeat_failure_delay   => :integer,
                        :initial_recovery_delay => :integer,
                        :ack_hash               => :string,
                        :notification_count     => :integer,
                        :condition              => :string,
                        :failing                => :boolean,
                        :alertable              => :boolean

      index_by :enabled, :failing, :alertable
      unique_index_by :name, :ack_hash

      # TODO validate uniqueness of :name, :ack_hash

      has_and_belongs_to_many :tags, :class_name => 'Flapjack::Data::Tag',
        :inverse_of => :checks

      has_sorted_set :scheduled_maintenances,
        :class_name => 'Flapjack::Data::ScheduledMaintenance',
        :key => :start_time, :order => :desc, :inverse_of => :check

      has_sorted_set :unscheduled_maintenances,
        :class_name => 'Flapjack::Data::UnscheduledMaintenance',
        :key => :start_time, :order => :desc, :inverse_of => :check

      has_sorted_set :states, :class_name => 'Flapjack::Data::State',
        :key => :created_at, :order => :desc, :inverse_of => :check

      # shortcut to expose the latest of the above to the API
      has_one :current_state, :class_name => 'Flapjack::Data::State',
        :inverse_of => :current_check

      has_sorted_set :latest_notifications, :class_name => 'Flapjack::Data::State',
        :key => :created_at, :order => :desc, :inverse_of => :latest_notifications_check,
        :after_remove => :destroy_states

      def self.destroy_states(check_id, *st_ids)
        # states won't be deleted if still referenced elsewhere -- see the State
        # before_destroy callback
        Flapjack::Data::State.intersect(:id => st_ids).destroy_all
      end

      # the following associations are used internally, for the notification
      # and alert queue inter-pikelet workflow
      has_one :most_severe, :class_name => 'Flapjack::Data::State',
        :inverse_of => :most_severe_check, :after_clear => :destroy_states

      has_many :notifications, :class_name => 'Flapjack::Data::Notification',
        :inverse_of => :check

      has_many :alerts, :class_name => 'Flapjack::Data::Alert',
        :inverse_of => :check

      # this can be called from the API (with no args) or from notifier.rb
      # (which will pass a severity to use, and an effective time)
      def alerting_media(opts = {})
        time = opts[:time] || Time.now
        severity = opts[:severity] || self.condition

        # return empty set if disabled, or in a maintenance period (for API only,
        # these will have been checked already in processor if called by notifier)
        if opts.empty?
          unless self.enabled
            return Flapjack::Data::Medium.empty
          end

          unless self.current_unscheduled_maintenance.nil?
            return Flapjack::Data::Medium.empty
          end

          start_range = Zermelo::Filters::IndexRange.new(nil, time, :by_score => true)
          end_range   = Zermelo::Filters::IndexRange.new(time, nil, :by_score => true)

          unless self.scheduled_maintenances.
            intersect(:start_time => start_range, :end_time => end_range).empty?

            return Flapjack::Data::Medium.empty
          end
        end

        # determine matching acceptors
        tag_ids = self.tags.ids

        acceptor_ids = matching_rule_ids(tag_ids, :blackhole => false, :severity => severity)
        acceptor_media_ids = Flapjack::Data::Rule.matching_media_ids(acceptor_ids,
          :time => time)

        return Flapjack::Data::Medium.empty if acceptor_media_ids.empty?

        # and matching rejectors
        rejector_ids = matching_rule_ids(tag_ids, :blackhole => true, :severity => severity)
        rejector_media_ids = Flapjack::Data::Rule.matching_media_ids(rejector_ids,
          :time => time)

        unless rejector_media_ids.empty?
          acceptor_media_ids -= rejector_media_ids
          return Flapjack::Data::Medium.empty if acceptor_media_ids.empty?
        end

        Flapjack::Data::Medium.intersect(:id => acceptor_media_ids)
      end

      def contacts
        # return empty set if disabled
        return Flapjack::Data::Contact.empty unless self.enabled

        # determine matching acceptors
        tag_ids = self.tags.ids
        time = Time.now

        acceptor_ids = matching_rule_ids(tag_ids, :blackhole => false,)
        acceptor_contact_ids = Flapjack::Data::Rule.matching_contact_ids(acceptor_ids,
          :time => time)
        return Flapjack::Data::Contact.empty if acceptor_contact_ids.empty?


        # and matching rejectors
        rejector_ids = matching_rule_ids(tag_ids, :blackhole => true)
        rejector_contact_ids = Flapjack::Data::Rule.matching_contact_ids(rejector_ids,
          :time => time)
        unless rejector_contact_ids.empty?
          acceptor_contact_ids -= rejector_contact_ids
          return Flapjack::Data::Contact.empty if acceptor_contact_ids.empty?
        end

        Flapjack::Data::Contact.intersect(:id => acceptor_contact_ids)
      end

      def matching_rule_ids(tag_ids, opts = {})
        severity = opts[:severity]
        blackhole = opts[:blackhole]

        matcher_by_strategy = {
          'global'   => nil,
          'all_tags' => proc {|rule_tag_ids| (rule_tag_ids - tag_ids).empty? },
          'any_tag'  => proc {|rule_tag_ids| !((rule_tag_ids & tag_ids).empty?) },
          'no_tag'   => proc {|rule_tag_ids| (rule_tag_ids & tag_ids).empty? }
        }

        matcher_by_strategy.each_with_object(Set.new) do |(strategy, matcher), memo|
          rules = Flapjack::Data::Rule.intersect(:enabled => true,
            :blackhole => blackhole, :strategy => strategy)
          unless severity.nil?
            rules = rules.intersect(:conditions_list => [nil, /(?:^|,)#{severity}(?:,|$)/])
          end

          if matcher.nil?
            memo.merge(rules.ids)
            next
          end

          rules.associated_ids_for(:tags).each_pair do |rule_id, rule_tag_ids|
            memo << rule_id if matcher.call(rule_tag_ids)
          end
        end
      end

      # end internal associations

      validates :name, :presence => true
      validates :enabled, :inclusion => {:in => [true, false]}

      validates :condition, :presence => true, :unless => proc {|c| c.failing.nil? }
      validates :failing, :inclusion => {:in => [true, false]},
        :unless => proc {|c| c.condition.nil? }

      validates :initial_failure_delay, :allow_nil => true,
        :numericality => {:greater_than_or_equal_to => 0, :only_integer => true}

      validates :repeat_failure_delay, :allow_nil => true,
        :numericality => {:greater_than_or_equal_to => 0, :only_integer => true}

      validates :initial_recovery_delay, :allow_nil => true,
        :numericality => {:greater_than_or_equal_to => 0, :only_integer => true}

      before_validation :create_ack_hash
      validates :ack_hash, :presence => true

      validates_with Flapjack::Data::Validators::IdValidator

      attr_accessor :count

      swagger_schema :Check do
        key :required, [:id, :type, :name, :enabled, :initial_failure_delay,
          :repeat_failure_delay, :initial_recovery_delay, :failing, :condition,
          :ack_hash]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Check.short_model_name.singular]
        end
        property :name do
          key :type, :string
        end
        property :enabled do
          key :type, :boolean
          key :enum, [true, false]
        end
        property :initial_failure_delay do
          key :type, :integer
        end
        property :repeat_failure_delay do
          key :type, :integer
        end
        property :initial_recovery_delay do
          key :type, :integer
        end
        property :failing do
          key :type, :boolean
          key :enum, [true, false]
        end
        property :condition do
          key :type, :string
          key :enum, Flapjack::Data::Condition.healthy.keys +
                       Flapjack::Data::Condition.unhealthy.keys
        end
        property :ack_hash do
          key :type, :string
        end
        property :relationships do
          key :"$ref", :CheckLinks
        end
      end

      swagger_schema :CheckLinks do
        property :alerting_media do
          key :"$ref", :MediaLinkage
        end
        property :contacts do
          key :"$ref", :ContactsLinkage
        end
        property :current_scheduled_maintenances do
          key :"$ref", :ScheduledMaintenancesLinkage
        end
        property :current_state do
          key :"$ref", :StateLinkage
        end
        property :current_unscheduled_maintenance do
          key :"$ref", :UnscheduledMaintenanceLinkage
        end
        property :latest_notifications do
          key :"$ref", :StatesLinkage
        end
        property :scheduled_maintenances do
          key :"$ref", :ScheduledMaintenancesLinkage
        end
        property :states do
          key :"$ref", :StatesLinkage
        end
        property :tags do
          key :"$ref", :TagsLinkage
        end
        property :unscheduled_maintenances do
          key :"$ref", :UnscheduledMaintenancesLinkage
        end
      end

      swagger_schema :CheckCreate do
        key :required, [:type, :name, :enabled]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Check.short_model_name.singular]
        end
        property :name do
          key :type, :string
        end
        property :enabled do
          key :type, :boolean
          key :enum, [true, false]
        end
        property :initial_failure_delay do
          key :type, :integer
        end
        property :repeat_failure_delay do
          key :type, :integer
        end
        property :initial_recovery_delay do
          key :type, :integer
        end
        property :relationships do
          key :"$ref", :CheckCreateLinks
        end
      end

      swagger_schema :CheckCreateLinks do
        property :tags do
          key :"$ref", :data_TagsReference
        end
      end

      swagger_schema :CheckUpdate do
        key :required, [:id, :type]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Check.short_model_name.singular]
        end
        property :name do
          key :type, :string
        end
        property :enabled do
          key :type, :boolean
          key :enum, [true, false]
        end
        property :initial_failure_delay do
          key :type, :integer
        end
        property :repeat_failure_delay do
          key :type, :integer
        end
        property :initial_recovery_delay do
          key :type, :integer
        end
        property :relationships do
          key :"$ref", :CheckUpdateLinks
        end
      end

      swagger_schema :CheckUpdateLinks do
        property :tags do
          key :"$ref", :data_TagsReference
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
            :attributes => [:name, :enabled, :initial_failure_delay,
                            :repeat_failure_delay, :initial_recovery_delay],
            :descriptions => {
              :singular => "Create a check.",
              :multiple => "Create checks."
            }
          ),
          :get => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:name, :enabled, :initial_failure_delay,
                            :repeat_failure_delay, :initial_recovery_delay,
                            :failing, :condition, :ack_hash],
            :descriptions => {
              :singular => "Returns data for a check.",
              :multiple => "Returns data for multiple check records."
            }
          ),
          :patch => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:name, :enabled, :initial_failure_delay,
                            :repeat_failure_delay, :initial_recovery_delay],
            :descriptions => {
              :singular => "Update a check.",
              :multiple => "Update checks."
            }
          ),
          :delete => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :descriptions => {
              :singular => "Delete a check.",
              :multiple => "Delete checks."
            }
          )
        }
      end

      def self.jsonapi_associations
        unless instance_variable_defined?('@jsonapi_associations')
          @jsonapi_associations = {
            :alerting_media => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :get => true,
              :number => :multiple, :link => true, :includable => true,
              :type => 'medium',
              :klass => Flapjack::Data::Medium,
              :callback_classes => [
                Flapjack::Data::Contact,
                Flapjack::Data::Rule,
                Flapjack::Data::Tag,
                Flapjack::Data::ScheduledMaintenance
              ],
              :descriptions => {
                :get => "While this check is failing, returns media records " \
                        "which are receiving notifications during this failure."
              }
            ),
            :contacts => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :get => true,
              :number => :multiple, :link => true, :includable => true,
              :type => 'contact',
              :klass => Flapjack::Data::Contact,
              :callback_classes => [
                Flapjack::Data::Rule,
                Flapjack::Data::Tag
              ],
              :descriptions => {
                :get => "Returns contacts whose notification rules will " \
                        "allow them to receive notifications for events on " \
                        "this check."
              }
            ),
            :current_scheduled_maintenances => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :get => true,
              :number => :multiple, :link => true, :includable => true,
              :type => 'scheduled_maintenance',
              :klass => Flapjack::Data::ScheduledMaintenance,
              :descriptions => {
                :get => "Returns scheduled maintenance periods currently in " \
                        " effect for this check."
              }
            ),
            :current_state => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :get => true,
              :number => :singular, :link => true, :includable => true,
              :descriptions => {
                :get => "Returns the current State record for this check."
              }
            ),
            :current_unscheduled_maintenance => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :get => true,
              :number => :singular, :link => true, :includable => true,
              :type => 'unscheduled_maintenance',
              :klass => Flapjack::Data::UnscheduledMaintenance,
              :descriptions => {
                :get => "If the check is currently acknowledged, returns the " \
                        "unscheduled maintenance period created for that."
              }
            ),
            :latest_notifications => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :get => true,
              :number => :multiple, :link => true, :includable => true,
              :descriptions => {
                :get => "Returns the most recent State records for each " \
                        "problem condition that produced notifications."
              }
            ),
            :scheduled_maintenances => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :get => true,
              :number => :multiple, :link => true, :includable => false,
              :descriptions => {
                :get => "Returns all scheduled maintenance periods for the " \
                        "check; default sort order is newest first."
              }
            ),
            :states => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :get => true,
              :number => :multiple, :link => true, :includable => false,
              :descriptions => {
                :get => "Returns all state records for the check; default " \
                        "sort order is newest first."
              }
            ),
            :tags => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :post => true, :get => true, :patch => true, :delete => true,
              :number => :multiple, :link => true, :includable => true,
              :descriptions => {
                :post => "Associate tags with this check.",
                :get => "Returns all tags linked to this check.",
                :patch => "Update the tags associated with this check.",
                :delete => "Delete associations between tags and this check."
              }
            ),
            :unscheduled_maintenances => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :get => true,
              :number => :multiple, :link => true, :includable => false,
              :descriptions => {
                :get => "Returns all unscheduled maintenance periods for the " \
                        "check; default sort order is newest first."
              }
            )
          }
          populate_association_data(@jsonapi_associations)
        end
        @jsonapi_associations
      end

      def in_scheduled_maintenance?(t = Time.now)
        !scheduled_maintenances_at(t).empty?
      end

      def current_scheduled_maintenances
        scheduled_maintenances_at(Time.now)
      end

      def in_unscheduled_maintenance?(t = Time.now)
        !unscheduled_maintenances_at(t).empty?
      end

      def current_unscheduled_maintenance
        unscheduled_maintenances_at(Time.now).all.first
      end

      # TODO allow summary to be changed as part of the termination
      def end_scheduled_maintenance(sched_maint, at_time)
        at_time = Time.at(at_time) unless at_time.is_a?(Time)

        if sched_maint.start_time >= at_time
          # the scheduled maintenance period is in the future
          self.scheduled_maintenances.remove(sched_maint)
          sched_maint.destroy
          return true
        elsif sched_maint.end_time >= at_time
          # it spans the current time, so we'll stop it at that point
          sched_maint.end_time = at_time
          sched_maint.save
          return true
        end

        false
      end

      def set_unscheduled_maintenance(unsched_maint, options = {})
        current_time = Time.now

        self.class.lock(Flapjack::Data::UnscheduledMaintenance,
          Flapjack::Data::State) do

          self.alertable = false
          self.save!

          # time_remaining
          if (unsched_maint.end_time - current_time) > 0
            self.clear_unscheduled_maintenance(unsched_maint.start_time)
          end

          self.unscheduled_maintenances << unsched_maint
        end
      end

      def clear_unscheduled_maintenance(end_time)
        Flapjack::Data::UnscheduledMaintenance.lock do
          t = Time.now
          start_range = Zermelo::Filters::IndexRange.new(nil, t, :by_score => true)
          end_range   = Zermelo::Filters::IndexRange.new(t, nil, :by_score => true)
          unsched_maints = self.unscheduled_maintenances.intersect(:start_time => start_range,
            :end_time => end_range)
          unsched_maints_count = unsched_maints.empty?
          unless unsched_maints_count == 0
            # FIXME log warning if count > 1
            unsched_maints.each do |usm|
              usm.end_time = end_time
              usm.save
            end
          end
        end
      end

      private

      # would need to be "#{entity.name}:#{name}" to be compatible with v1, but
      # to support name changes it must be something invariant
      def create_ack_hash
        return unless self.ack_hash.nil? # :on => :create isn't working
        self.id = self.class.generate_id if self.id.nil?
        self.ack_hash = Digest.hexencode(Digest::SHA1.new.digest(self.id))[0..7].downcase
      end

      def scheduled_maintenances_at(t)
        start_range = Zermelo::Filters::IndexRange.new(nil, t, :by_score => true)
        end_range   = Zermelo::Filters::IndexRange.new(t, nil, :by_score => true)
        self.scheduled_maintenances.intersect(:start_time => start_range,
          :end_time => end_range)
      end

      def unscheduled_maintenances_at(t)
        start_range = Zermelo::Filters::IndexRange.new(nil, t, :by_score => true)
        end_range   = Zermelo::Filters::IndexRange.new(t, nil, :by_score => true)
        self.unscheduled_maintenances.intersect(:start_time => start_range,
          :end_time => end_range)
      end
    end
  end
end
