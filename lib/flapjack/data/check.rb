#!/usr/bin/env ruby

require 'digest'

require 'swagger/blocks'

require 'zermelo/records/redis_record'

require 'flapjack/data/validators/id_validator'

require 'flapjack/data/condition'
require 'flapjack/data/medium'
require 'flapjack/data/scheduled_maintenance'
require 'flapjack/data/state'
require 'flapjack/data/tag'
require 'flapjack/data/unscheduled_maintenance'

require 'flapjack/gateways/jsonapi/data/associations'

module Flapjack

  module Data

    class Check

      include Zermelo::Records::RedisRecord
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false
      include Flapjack::Gateways::JSONAPI::Data::Associations
      include Swagger::Blocks

      # NB: state could be retrieved from states.last instead -- summary, details
      # and last_update can change without a new check_state being added though

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
        :inverse_of => :checks, :after_add => :recalculate_routes,
        :after_remove => :recalculate_routes,
        :related_class_names => ['Flapjack::Data::Rule', 'Flapjack::Data::Route']

      def recalculate_routes(*t)
        self.routes.destroy_all
        return if self.tags.empty?

        # find all rules matching these tags
        generic_rule_ids = Flapjack::Data::Rule.intersect(:has_tags => false).ids

        tag_ids = self.tags.ids

        tag_rules_ids = Flapjack::Data::Tag.intersect(:id => tag_ids).
          associated_ids_for(:rules)

        return if tag_rules_ids.empty?

        all_rules_for_tags_ids = Set.new(tag_rules_ids.values).flatten

        return if all_rules_for_tags_ids.empty?

        rule_tags_ids = Flapjack::Data::Rule.intersect(:id => all_rules_for_tags_ids).
          associated_ids_for(:tags)

        rule_tags_ids.delete_if {|rid, tids| (tids - tag_ids).size > 0 }

        rule_ids = rule_tags_ids.keys | generic_rule_ids.to_a

        return if rule_ids.empty?

        Flapjack::Data::Rule.intersect(:id => rule_ids).each do |r|
          route = Flapjack::Data::Route.new(:is_alerting => false,
            :conditions_list => r.conditions_list)
          route.save

          r.routes << route
          self.routes << route
        end
      end

      has_sorted_set :states, :class_name => 'Flapjack::Data::State',
        :key => :timestamp, :inverse_of => :check

      has_one :most_severe, :class_name => 'Flapjack::Data::State',
        :inverse_of => :most_severe_check

      has_sorted_set :latest_notifications, :class_name => 'Flapjack::Data::Entry',
        :key => :timestamp, :inverse_of => :latest_notifications_check,
        :after_remove => :removed_latest_notification

      def removed_latest_notification(entry)
        Flapjack::Data::Entry.delete_if_unlinked(entry)
      end

      def last_update
        s = self.states.last
        return if s.nil?
        s.entries.last
      end

      def last_change
        s = self.states.last
        return if s.nil?
        s.entries.first
      end

      # keep two indices for each, so that we can query on their intersection
      has_sorted_set :scheduled_maintenances_by_start,
        :class_name => 'Flapjack::Data::ScheduledMaintenance',
        :key => :start_time, :inverse_of => :check_by_start
      has_sorted_set :scheduled_maintenances_by_end,
        :class_name => 'Flapjack::Data::ScheduledMaintenance',
        :key => :end_time, :inverse_of => :check_by_end

      has_sorted_set :unscheduled_maintenances_by_start,
        :class_name => 'Flapjack::Data::UnscheduledMaintenance',
        :key => :start_time, :inverse_of => :check_by_start
      has_sorted_set :unscheduled_maintenances_by_end,
        :class_name => 'Flapjack::Data::UnscheduledMaintenance',
        :key => :end_time, :inverse_of => :check_by_end

      # the following associations are used internally, for the notification
      # and alert queue inter-pikelet workflow

      has_many :alerts, :class_name => 'Flapjack::Data::Alert',
        :inverse_of => :check

      has_and_belongs_to_many :routes, :class_name => 'Flapjack::Data::Route',
        :inverse_of => :checks

      validates :name, :presence => true
      validates :enabled, :inclusion => {:in => [true, false]}

      validates :condition, :presence => true, :unless => proc {|c| c.failing.nil? }
      validates :failing, :inclusion => {:in => [true, false]}, :unless => proc {|c| c.condition.nil? }

      validates :initial_failure_delay, :allow_nil => true,
        :numericality => {:greater_than_or_equal_to => 0, :only_integer => true}

      validates :repeat_failure_delay, :allow_nil => true,
        :numericality => {:greater_than_or_equal_to => 0, :only_integer => true}

      before_validation :create_ack_hash
      validates :ack_hash, :presence => true

      validates_with Flapjack::Data::Validators::IdValidator

      attr_accessor :count

      def self.jsonapi_type
        self.name.demodulize.underscore
      end

      swagger_schema :Check do
        key :required, [:id, :type, :name, :enabled, :failing]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Check.jsonapi_type.downcase]
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
        property :links do
          key :"$ref", :CheckLinks
        end
      end

      swagger_schema :CheckLinks do
        key :required, [:self, :tags]
        property :self do
          key :type, :string
          key :format, :url
        end
        property :tags do
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
          key :enum, [Flapjack::Data::Check.jsonapi_type.downcase]
        end
        property :name do
          key :type, :string
        end
        property :enabled do
          key :type, :boolean
          key :enum, [true, false]
        end
        property :links do
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
          key :enum, [Flapjack::Data::Check.jsonapi_type.downcase]
        end
        property :name do
          key :type, :string
        end
        property :enabled do
          key :type, :boolean
          key :enum, [true, false]
        end
        property :links do
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
        [:post, :get, :patch, :delete]
      end

      def self.jsonapi_attributes
        {
          :post  => [:name, :enabled],
          :get   => [:name, :enabled, :ack_hash, :failing, :condition],
          :patch => [:name, :enabled]
        }
      end

      def self.jsonapi_associations
        {
          :singular => [],
          :multiple => [:scheduled_maintenances, :tags,
                        :unscheduled_maintenances]
        }
      end

      def in_scheduled_maintenance?
        return false if scheduled_maintenance_ids_at(Time.now).empty?
        self.routes.intersect(:is_alerting => true).each do |route|
          route.is_alerting = false
          route.save
        end
        true
      end

      def in_unscheduled_maintenance?
        !unscheduled_maintenance_ids_at(Time.now).empty?
      end

      def add_scheduled_maintenance(sched_maint)
        self.scheduled_maintenances_by_start << sched_maint
        self.scheduled_maintenances_by_end << sched_maint
      end

      # TODO allow summary to be changed as part of the termination
      def end_scheduled_maintenance(sched_maint, at_time)
        at_time = Time.at(at_time) unless at_time.is_a?(Time)

        if sched_maint.start_time >= at_time
          # the scheduled maintenance period is in the future
          self.scheduled_maintenances_by_start.delete(sched_maint)
          self.scheduled_maintenances_by_end.delete(sched_maint)
          sched_maint.destroy
          return true
        end

        if sched_maint.end_time >= at_time
          # it spans the current time, so we'll stop it at that point
          # need to remove it from the sorted_set that uses the end_time as a key,
          # change and re-add -- see https://github.com/ali-graham/zermelo/issues/1
          # TODO should this be in a multi/exec block?
          self.scheduled_maintenances_by_end.delete(sched_maint)
          sched_maint.end_time = at_time
          sched_maint.save
          self.scheduled_maintenances_by_end.add(sched_maint)
          return true
        end

        false
      end

      # def current_scheduled_maintenance
      def scheduled_maintenance_at(at_time)
        current_sched_ms = scheduled_maintenance_ids_at(at_time).map {|id|
          Flapjack::Data::ScheduledMaintenance.find_by_id(id)
        }
        return if current_sched_ms.empty?
        # if multiple scheduled maintenances found, find the end_time furthest in the future
        current_sched_ms.max_by(&:end_time)
      end

      def unscheduled_maintenance_at(at_time)
        current_unsched_ms = unscheduled_maintenance_ids_at(at_time).map {|id|
          Flapjack::Data::UnscheduledMaintenance.find_by_id(id)
        }
        return if current_unsched_ms.empty?
        # if multiple unscheduled maintenances found, find the end_time furthest in the future
        current_unsched_ms.max_by(&:end_time)
      end

      def set_unscheduled_maintenance(unsched_maint, options = {})
        current_time = Time.now

        self.class.lock(Flapjack::Data::UnscheduledMaintenance,
          Flapjack::Data::Route, Flapjack::Data::State) do

          # time_remaining
          if (unsched_maint.end_time - current_time) > 0
            self.clear_unscheduled_maintenance(unsched_maint.start_time)
          end

          self.unscheduled_maintenances_by_start << unsched_maint
          self.unscheduled_maintenances_by_end << unsched_maint

          # TODO add an ack action to the event state directly, uless this is the
          # result of one
          if options[:create_state].is_a?(TrueClass)
            last_state = self.states.last
            ack_state = Flapjack::Data::State.new
            # TODO set state data
            ack_state.save
            self.states << ack_state
          end

          self.routes.intersect(:is_alerting => true).each do |route|
            route.is_alerting = false
            route.save
          end
        end
      end

      def clear_unscheduled_maintenance(end_time)
        return unless unsched_maint = unscheduled_maintenance_at(Time.now)
        # need to remove it from the sorted_set that uses the end_time as a key,
        # change and re-add -- see https://github.com/ali-graham/zermelo/issues/1
        self.class.lock(Flapjack::Data::UnscheduledMaintenance) do
          self.unscheduled_maintenances_by_end.delete(unsched_maint)
          unsched_maint.end_time = end_time
          unsched_maint.save
          self.unscheduled_maintenances_by_end.add(unsched_maint)
        end
      end

      # candidate rules are all rules for which
      #   (rule.tags.ids - check.tags.ids).empty?
      # this includes generic rules, i.e. ones with no tags

      # A generic rule in Flapjack v2 means that it applies to all checks, not
      # just all checks the contact is separately regeistered for, as in v1.
      # These are not automatically created for users any more, but can be
      # deliberately configured.

      # returns array with two hashes [{contact_id => Set<rule_ids>},
      #   {rule_id => Set<route_ids>}]

      def rule_ids_and_route_ids(opts = {})
        severity = opts[:severity]

        r_ids = self.routes.ids

        Flapjack.logger.debug {
          "severity: #{severity}\n" \
          "Matching routes before severity (#{r_ids.size}): #{r_ids.inspect}"
        }
        return [{}, {}] if r_ids.empty?

        check_routes = self.routes

        unless severity.nil? || Flapjack::Data::Condition.healthy.include?(severity)
          check_routes = check_routes.
            intersect(:conditions_list => [nil, /(?:^|,)#{severity}(?:,|$)/])
        end

        route_ids = check_routes.ids
        return [{}, {}] if route_ids.empty?

        Flapjack.logger.debug {
          "Matching routes after severity (#{route_ids.size}): #{route_ids.inspect}"
        }

        route_ids_by_rule_id = Flapjack::Data::Route.intersect(:id => route_ids).
          associated_ids_for(:rule, :inversed => true)

        rule_ids = route_ids_by_rule_id.keys

        Flapjack.logger.debug {
          "Matching rules for routes (#{rule_ids.size}): #{rule_ids.inspect}"
        }

        # TODO could maybe also eliminate rules with no media here?
        rule_ids_by_contact_id = Flapjack::Data::Rule.intersect(:id => rule_ids).
          associated_ids_for(:contact, :inversed => true)

        [rule_ids_by_contact_id, route_ids_by_rule_id]
      end

      def self.pagerduty_credentials_for(check_ids)
        rule_ids_by_check_id = Flapjack::Data::Check.rules_for(check_ids)

        rule_ids_by_media_id = Flapjack::Data::Medium.
          intersect(:transport => 'pagerduty').associated_ids_for(:rules)

        return nil if rule_ids_by_media_id.empty? ||
          rule_ids_by_media_id.values.all? {|r| r.empty? }

        rule_ids = Set.new(rule_ids_by_media_id.values).flatten

        media_ids_by_rule_id = Flapjack::Data::Rule.
          intersect(:id => rule_ids).associated_ids_for(:media)

        pagerduty_objs_by_id = Flapjack::Data::Medium.find_by_ids!(rule_ids_by_media_id.keys)

        Flapjack::Data::Check.intersect(:id => check_ids).all.each_with_object({}) do |check, memo|
          memo[check] = rule_ids_by_check_id[check.id].each_with_object([]) do |rule_id, m|
            m += media_ids_by_rule_id[rule_id].collect do |media_id|
              medium = pagerduty_objs_by_id[media_id]
              ud = medium.userdata || {}
              {
                'service_key' => medium.address,
                'subdomain'   => ud['subdomain'],
                'username'    => ud['username'],
                'password'    => ud['password'],
              }
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

      def scheduled_maintenance_ids_at(at_time)
        at_time = Time.at(at_time) unless at_time.is_a?(Time)

        start_prior_ids = self.scheduled_maintenances_by_start.
          intersect_range(nil, at_time.to_i, :by_score => true).ids
        end_later_ids = self.scheduled_maintenances_by_end.
          intersect_range(at_time.to_i + 1, nil, :by_score => true).ids

        start_prior_ids & end_later_ids
      end

      def unscheduled_maintenance_ids_at(at_time)
        at_time = Time.at(at_time) unless at_time.is_a?(Time)

        start_prior_ids = self.unscheduled_maintenances_by_start.
          intersect_range(nil, at_time.to_i + 1, :by_score => true).ids
        end_later_ids = self.unscheduled_maintenances_by_end.
          intersect_range(at_time.to_i, nil, :by_score => true).ids

        start_prior_ids & end_later_ids
      end

    end

  end

end
