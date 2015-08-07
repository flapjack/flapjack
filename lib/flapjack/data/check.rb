#!/usr/bin/env ruby

require 'digest'

require 'swagger/blocks'

require 'zermelo/records/redis'

require 'flapjack/data/extensions/short_name'
require 'flapjack/data/validators/id_validator'

require 'flapjack/data/blackhole'
require 'flapjack/data/condition'
require 'flapjack/data/medium'
require 'flapjack/data/scheduled_maintenance'
require 'flapjack/data/state'
require 'flapjack/data/tag'
require 'flapjack/data/unscheduled_maintenance'

require 'flapjack/data/extensions/associations'
require 'flapjack/gateways/jsonapi/data/join_descriptor'
require 'flapjack/gateways/jsonapi/data/method_descriptor'

module Flapjack

  module Data

    class Check

      include Zermelo::Records::Redis
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false
      include Swagger::Blocks

      include Flapjack::Data::Extensions::Associations
      include Flapjack::Data::Extensions::ShortName

      define_attributes :name                  => :string,
                        :enabled               => :boolean,
                        :ack_hash              => :string,
                        :initial_failure_delay => :integer,
                        :repeat_failure_delay  => :integer,
                        :notification_count    => :integer,
                        :condition             => :string,
                        :failing               => :boolean

      index_by :enabled, :failing
      unique_index_by :name, :ack_hash

      # TODO validate uniqueness of :name, :ack_hash

      # TODO verify that callbacks are called no matter which side
      # of the association fires the initial event
      has_and_belongs_to_many :tags, :class_name => 'Flapjack::Data::Tag',
        :inverse_of => :checks, :after_add => :changed_tags,
        :after_remove => :changed_tags,
        :related_class_names => ['Flapjack::Data::Contact',
          'Flapjack::Data::Rule', 'Flapjack::Data::Route']

      def self.changed_tags(check_id, *t_ids)
        Flapjack::Data::Check.find_by_id!(check_id).recalculate_routes
      end

      def recalculate_routes
        self.routes.destroy_all
        self.contacts.clear
        return if self.tags.empty?

        # find all rules matching these tags
        generic_rule_ids = Flapjack::Data::Rule.intersect(:has_tags => false).ids

        tag_ids = self.tags.ids

        all_rules_for_tags_ids = Flapjack::Data::Tag.intersect(:id => tag_ids).
          associated_ids_for(:rules).values.reduce(Set.new, :|)

        return if all_rules_for_tags_ids.empty?

        rule_tags_ids = Flapjack::Data::Rule.intersect(:id => all_rules_for_tags_ids).
          associated_ids_for(:tags)

        rule_tags_ids.delete_if {|rid, tids| (tids - tag_ids).size > 0 }

        rule_ids = rule_tags_ids.keys | generic_rule_ids.to_a

        return if rule_ids.empty?

        contact_ids = Flapjack::Data::Rule.intersect(:id => rule_ids).
          associated_ids_for(:contact).values

        self.contacts.add_ids(*contact_ids) unless contact_ids.empty?

        Flapjack::Data::Rule.intersect(:id => rule_ids).each do |r|
          route = Flapjack::Data::Route.new(:alertable => false,
            :conditions_list => r.conditions_list)
          route.save

          r.routes << route
          self.routes << route
        end
      end

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

      has_and_belongs_to_many :contacts, :class_name => 'Flapjack::Data::Contact',
        :inverse_of => :checks

      # the following associations are used internally, for the notification
      # and alert queue inter-pikelet workflow
      has_one :most_severe, :class_name => 'Flapjack::Data::State',
        :inverse_of => :most_severe_check, :after_clear => :destroy_states

      has_many :notifications, :class_name => 'Flapjack::Data::Notification',
        :inverse_of => :check

      has_many :alerts, :class_name => 'Flapjack::Data::Alert',
        :inverse_of => :check

      has_and_belongs_to_many :routes, :class_name => 'Flapjack::Data::Route',
        :inverse_of => :checks

      # this can be called from the API (with no args) or from notifier.rb
      # (which will pass routes to use, and an effective time)
      def alerting_media(opts = {})
        time = opts[:time] || Time.now

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

        alert_routes = opts[:routes] || self.routes.intersect(:alertable => true)
        route_rule_ids = alert_routes.associated_ids_for(:rule).values.uniq

        return Flapjack::Data::Medium.empty if route_rule_ids.empty?

        # if a rule has no media, it's irrelevant here
        rule_ids_by_contact_id = Flapjack::Data::Rule.
          intersect(:id => route_rule_ids, :has_media => true).
          associated_ids_for(:contact, :inversed => true)

        contacts = rule_ids_by_contact_id.empty? ? [] :
          Flapjack::Data::Contact.find_by_ids(*rule_ids_by_contact_id.keys)

        matching_rule_ids = contacts.inject([]) do |memo, contact|
          timezone = contact.time_zone || @default_contact_timezone
          rule_ids = rule_ids_by_contact_id[contact.id]

          unless rule_ids.empty?
             memo += Flapjack::Data::Rule.intersect(:id => rule_ids).select {|rule|
              rule.is_occurring_at?(time, timezone)
            }.map(&:id)
          end
          memo
        end

        return Flapjack::Data::Medium.empty if matching_rule_ids.empty?

        media_ids = Flapjack::Data::Rule.intersect(:id => matching_rule_ids).
          associated_ids_for(:media).values.reduce(:|)

        return Flapjack::Data::Medium.empty if media_ids.empty?

        # remove any media for which any medium.blackhole.tags - self.tags is empty
        blackhole_ids_by_media_id = Flapjack::Data::Medium.
          intersect(:id => media_ids).associated_ids_for(:blackholes)

        blackhole_ids = blackhole_ids_by_media_id.values.reduce(:|)

        unless blackhole_ids.empty?
          tag_ids = self.tags.ids

          tag_ids_by_blackhole_id = Flapjack::Data::Blackhole.
            intersect(:id => blackhole_ids).associated_ids_for(:tags)

          media_ids -= blackhole_ids_by_media_id.each_with_object([]) do |(media_id, media_blackhole_ids), memo|
            memo << media_id if media_blackhole_ids.any? {|mb_id|
              bh_tag_ids = tag_ids_by_blackhole_id[mb_id]
              (bh_tag_ids - tag_ids).empty?
            }
          end

          return Flapjack::Data::Medium.empty if media_ids.empty?
        end

        Flapjack::Data::Medium.intersect(:id => media_ids)
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

      before_validation :create_ack_hash
      validates :ack_hash, :presence => true

      validates_with Flapjack::Data::Validators::IdValidator

      attr_accessor :count

      swagger_schema :Check do
        key :required, [:id, :type, :name, :enabled, :failing]
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
        property :failing do
          key :type, :boolean
          key :enum, [true, false]
        end
        property :condition do
          key :type, :string
          key :enum, Flapjack::Data::Condition.healthy.keys +
                       Flapjack::Data::Condition.unhealthy.keys
        end
        property :relationships do
          key :"$ref", :CheckLinks
        end
      end

      swagger_schema :CheckLinks do
        key :required, [:self, :alerting_media, :contacts, :current_state,
                        :latest_notifications, :scheduled_maintenance,
                        :states, :tags, :unscheduled_maintenances]
        property :self do
          key :type, :string
          key :format, :url
        end
        property :alerting_media do
          key :type, :string
          key :format, :url
        end
        property :contacts do
          key :type, :string
          key :format, :url
        end
        property :current_state do
          key :type, :string
          key :format, :url
        end
        property :latest_notifications do
          key :type, :string
          key :format, :url
        end
        property :scheduled_maintenances do
          key :type, :string
          key :format, :url
        end
        property :states do
          key :type, :string
          key :format, :url
        end
        property :tags do
          key :type, :string
          key :format, :url
        end
        property :unscheduled_maintenances do
          key :type, :string
          key :format, :url
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
        property :relationships do
          key :"$ref", :CheckChangeLinks
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
        property :relationships do
          key :"$ref", :CheckChangeLinks
        end
      end

      swagger_schema :CheckChangeLinks do
        property :scheduled_maintenances do
          key :"$ref", :jsonapi_UnscheduledMaintenancesLinkage
        end
        property :tags do
          key :"$ref", :jsonapi_TagsLinkage
        end
        property :unscheduled_maintenances do
          key :"$ref", :jsonapi_ScheduledMaintenancesLinkage
        end
      end

      def self.jsonapi_methods
        @jsonapi_methods ||= {
          :post => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:name, :enabled]
          ),
          :get => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:name, :enabled, :ack_hash, :failing, :condition]
          ),
          :patch => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:name, :enabled]
          ),
          :delete => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
          )
        }
      end

      def self.jsonapi_associations
        if @jsonapi_associations.nil?
          @jsonapi_associations = {
            :alerting_media => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :get => true,
              :number => :multiple, :link => true, :includable => true,
              :type => 'medium',
              :klass => Flapjack::Data::Medium,
              :related_klasses => [
                Flapjack::Data::Blackhole,
                Flapjack::Data::Contact,
                Flapjack::Data::Route,
                Flapjack::Data::Rule,
                Flapjack::Data::ScheduledMaintenance
              ]
            ),
            :contacts => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :get => true,
              :number => :multiple, :link => true, :includable => true
            ),
            :current_scheduled_maintenances => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :get => true,
              :number => :multiple, :link => true, :includable => true,
              :type => 'scheduled_maintenance',
              :klass => Flapjack::Data::ScheduledMaintenance
            ),
            :current_state => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :get => true,
              :number => :singular, :link => true, :includable => true
            ),
            :current_unscheduled_maintenance => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :get => true,
              :number => :singular, :link => true, :includable => true,
              :type => 'unscheduled_maintenance',
              :klass => Flapjack::Data::UnscheduledMaintenance
            ),
            :latest_notifications => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :get => true,
              :number => :multiple, :link => true, :includable => true
            ),
            :scheduled_maintenances => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :get => true,
              :number => :multiple, :link => true, :includable => false
            ),
            :states => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :get => true,
              :number => :multiple, :link => true, :includable => false
            ),
            :tags => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :post => true, :get => true, :patch => true, :delete => true,
              :number => :multiple, :link => true, :includable => true
            ),
            :unscheduled_maintenances => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :get => true,
              :number => :multiple, :link => true, :includable => false
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
          Flapjack::Data::Route, Flapjack::Data::State) do

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
