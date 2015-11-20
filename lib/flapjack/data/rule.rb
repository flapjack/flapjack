#!/usr/bin/env ruby

require 'set'

require 'active_support/inflector'
require 'active_support/core_ext/hash/slice'

require 'ice_cube'
require 'icalendar'
require 'swagger/blocks'

require 'zermelo/records/redis'

require 'flapjack/utility'

require 'flapjack/data/extensions/short_name'
require 'flapjack/data/validators/id_validator'

require 'flapjack/data/extensions/associations'
require 'flapjack/gateways/jsonapi/data/join_descriptor'
require 'flapjack/gateways/jsonapi/data/method_descriptor'

module Flapjack
  module Data
    class Rule

      STRATEGIES = ['global', 'any_tag', 'all_tags', 'no_tag']

      extend Flapjack::Utility

      include Zermelo::Records::RedisSet
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false
      include Swagger::Blocks

      include Flapjack::Data::Extensions::Associations
      include Flapjack::Data::Extensions::ShortName

      # regex_* properties have been removed as they encourage loose binding
      # against check names, which may change. Do client-side grouping and
      # create a tag!

      define_attributes :name => :string,
                        :enabled => :boolean,
                        :blackhole => :boolean,
                        :strategy => :string,
                        :conditions_list => :string,
                        :has_media => :boolean,
                        :time_restriction_ical => :string

      index_by :name, :enabled, :blackhole, :strategy, :conditions_list, :has_media

      validates_with Flapjack::Data::Validators::IdValidator

      validates :enabled, :inclusion => {:in => [true, false]}
      validates :blackhole, :inclusion => {:in => [true, false]}
      validates :strategy, :inclusion => {:in => Flapjack::Data::Rule::STRATEGIES}

      validates_each :time_restriction_ical do |record, att, value|
        unless record.valid_time_restriction_ical?
          record.errors.add(:time_restriction_ical, 'is not valid ICAL syntax')
        end
      end

      belongs_to :contact, :class_name => 'Flapjack::Data::Contact',
        :inverse_of => :rules

      has_and_belongs_to_many :media, :class_name => 'Flapjack::Data::Medium',
        :inverse_of => :rules, :after_add => :media_added,
        :after_remove => :media_removed

      has_and_belongs_to_many :tags, :class_name => 'Flapjack::Data::Tag',
        :inverse_of => :rules

      def initialize(attributes = {})
        super
        send(:"attribute=", 'has_media', false)
      end

      def time_restriction
        return if time_restriction_ical.nil? || !valid_time_restriction_ical?
        IceCube::Schedule.from_ical(time_restriction_ical)
      end

      def time_restriction=(restriction)
        if restriction.nil?
          self.time_restriction_ical = nil
          return
        end
        unless restriction.is_a?(IceCube::Schedule)
          raise "Invalid data type for time_restriction= (#{restriction.class.name})"
        end
        # ice_cube ignores time zone info when parsing ical, so we'll enforce UTC
        # and cast to the contact's preferred time zone as appropriate when using
        # (this should also handle the case of the user changing her timezone)
        restriction.start_time = restriction.start_time.nil? ? nil : restriction.start_time.utc
        restriction.end_time = restriction.end_time.nil? ? nil : restriction.end_time.utc
        self.time_restriction_ical = restriction.to_ical
      end

      def valid_time_restriction_ical?
        return true if time_restriction_ical.nil?
        wrapped_value = ['BEGIN:VCALENDAR',
                         'VERSION:2.0',
                         'PRODID:validationid',
                         'CALSCALE:GREGORIAN',
                         'BEGIN:VEVENT',
                         time_restriction_ical,
                         'END:VEVENT',
                         'END:VCALENDAR'].join("\n")

        # icalendar is noisy with errors
        old_icalendar_log_level = ::Icalendar.logger.level
        ::Icalendar.logger.level = ::Logger::FATAL
        icalendar = ::Icalendar.parse(wrapped_value)
        ::Icalendar.logger.level = old_icalendar_log_level

        !(icalendar.empty? || icalendar.first.events.empty? ||
          !icalendar.first.events.first.valid?)
      end

      # nil time_restriction matches
      def is_occurring_at?(time, time_zone = Time.zone)
        return true if time_restriction.nil?
        time_restriction.occurring_at?(time.in_time_zone(time_zone))
      end

      def self.media_added(rule_id, *m_ids)
        rule = self.find_by_id!(rule_id)
        rule.has_media = true
        rule.save!
      end

      def self.media_removed(rule_id, *m_ids)
        rule = self.find_by_id!(rule_id)
        rule.has_media = rule.media.empty?
        rule.save!
      end

      # called by medium.checks
      # no global rules in the passed rule data
      # rule_ids will be all acceptors
      # (blackhole == false) or all rejectors (blackhole == true)
      def self.matching_checks(rule_ids)
        m_checks = ['all_tags', 'any_tag', 'no_tag'].inject(nil) do |memo, strategy|
          tag_ids_by_rule_id = self.intersect(:strategy => strategy,
            :id => rule_ids).associated_ids_for(:tags)

          checks = checks_for_tag_match(strategy, tag_ids_by_rule_id)

          memo = if memo.nil?
            Flapjack::Data::Check.intersect(:id => checks)
          else
            memo.union(:id => checks)
          end
        end

        return Flapjack::Data::Check.empty if m_checks.nil?
        m_checks
      end

      # called by check.contacts, rule_ids will be all acceptors
      # (blackhole == false) or all rejectors (blackhole == true)
      def self.matching_contact_ids(rule_ids, opts = {})
        time = opts[:time] || Time.now
        contact_rules = self.intersect(:id => rule_ids)

        matching_ids = apply_time_restriction(contact_rules, time).
          map(&:id)

        self.intersect(:id => matching_ids).
          associated_ids_for(:contact, :inversed => true).keys
      end

      # called by check.alerting_media, rule_ids will be all acceptors
      # (blackhole == false) or all rejectors (blackhole == true)
      def self.matching_media_ids(rule_ids, opts = {})
        time = opts[:time] || Time.now

        # if a rule has no media, it's irrelevant here
        media_rules = self.intersect(:id => rule_ids, :has_media => true)

        matching_ids = apply_time_restriction(media_rules, time).
          map(&:id)

        self.intersect(:id => matching_ids).
          associated_ids_for(:media).values.reduce(Set.new, :|)
      end

      swagger_schema :Rule do
        key :required, [:id, :type, :enabled, :blackhole, :strategy]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Rule.short_model_name.singular]
        end
        property :name do
          key :type, :string
        end
        property :enabled do
          key :type, :boolean
        end
        property :blackhole do
          key :type, :boolean
        end
        property :strategy do
          key :type, :string
          key :enum, Flapjack::Data::Rule::STRATEGIES
        end
        property :conditions_list do
          key :type, :string
        end
        property :time_restriction_ical do
          key :type, :string
        end
        property :relationships do
          key :"$ref", :RuleLinks
        end
      end

      swagger_schema :RuleLinks do
        key :required, [:contact, :media, :tags]
        property :contact do
          key :"$ref", :ContactLinkage
        end
        property :media do
          key :"$ref", :MediaLinkage
        end
        property :tags do
          key :"$ref", :TagsLinkage
        end
      end

      swagger_schema :RuleCreate do
        key :required, [:type, :enabled, :blackhole, :strategy]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Rule.short_model_name.singular]
        end
        property :name do
          key :type, :string
        end
        property :enabled do
          key :type, :boolean
        end
        property :blackhole do
          key :type, :boolean
        end
        property :strategy do
          key :type, :string
          key :enum, Flapjack::Data::Rule::STRATEGIES
        end
        property :conditions_list do
          key :type, :string
        end
        property :time_restriction_ical do
          key :type, :string
        end
        property :relationships do
          key :"$ref", :RuleCreateLinks
        end
      end

      swagger_schema :RuleCreateLinks do
        key :required, [:contact]
        property :contact do
          key :"$ref", :data_ContactReference
        end
        property :media do
          key :"$ref", :data_MediaReference
        end
        property :tags do
          key :"$ref", :data_TagsReference
        end
      end

      swagger_schema :RuleUpdate do
        key :required, [:id, :type]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Rule.short_model_name.singular]
        end
        property :name do
          key :type, :string
        end
        property :enabled do
          key :type, :boolean
        end
        property :blackhole do
          key :type, :boolean
        end
        property :strategy do
          key :type, :string
          key :enum, Flapjack::Data::Rule::STRATEGIES
        end
        property :conditions_list do
          key :type, :string
        end
        property :time_restriction_ical do
          key :type, :string
        end
        property :relationships do
          key :"$ref", :RuleUpdateLinks
        end
      end

      swagger_schema :RuleUpdateLinks do
        property :media do
          key :"$ref", :data_MediaReference
        end
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
            :attributes => [:name, :enabled, :blackhole, :strategy, :conditions_list,
              :time_restriction_ical],
            :descriptions => {
              :singular => "Create a notification rule.",
              :multiple => "Create notification rules."
            }
          ),
          :get => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:name, :enabled, :blackhole, :strategy, :conditions_list,
              :time_restriction_ical],
            :descriptions => {
              :singular => "Get data for a notification rule.",
              :multiple => "Get data for multiple notification rules."
            }
          ),
          :patch => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:name, :enabled, :blackhole, :strategy, :conditions_list,
              :time_restriction_ical],
            :descriptions => {
              :singular => "Update a notification rule.",
              :multiple => "Update notification rules."
            }
          ),
          :delete => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :descriptions => {
              :singular => "Delete a notification rule.",
              :multiple => "Delete notification rules."
            }
          )
        }
      end

      def self.jsonapi_associations
        unless instance_variable_defined?('@jsonapi_associations')
          @jsonapi_associations = {
            :contact => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :post => true, :get => true,
              :number => :singular, :link => true, :includable => true,
              :descriptions => {
                :post => "Set a contact for a rule during rule creation (required).",
                :get => "Get the contact a rule belongs to."
              }
            ),
            :media => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :post => true, :get => true, :patch => true, :delete => true,
              :number => :multiple, :link => true, :includable => true,
              :descriptions => {
                :post => "Associate this rule with media on rule creation.",
                :get => "Get the media this rule is associated with.",
                :patch => "Update the media this rule is associated with.",
                :delete => "Delete associations between this rule and media."
              }
            ),
            :tags => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :post => true, :get => true, :patch => true, :delete => true,
              :number => :multiple, :link => true, :includable => true,
              :descriptions => {
                :post => "Associate tags with this rule.",
                :get => "Returns all tags linked to this rule.",
                :patch => "Update the tags associated with this rule.",
                :delete => "Delete associations between tags and this rule."
              }
            )
          }
          populate_association_data(@jsonapi_associations)
        end
        @jsonapi_associations
      end

      protected

      def self.apply_time_restriction(rules, time)
        # filter the rules by time restriction
        rule_ids_by_contact_id = rules.associated_ids_for(:contact, :inversed => true)

        rule_contacts = rule_ids_by_contact_id.empty? ? [] :
          Flapjack::Data::Contact.find_by_ids(*rule_ids_by_contact_id.keys)

        time_zones_by_rule_id = rule_contacts.each_with_object({}) do |c, memo|
          rule_ids_by_contact_id[c.id].each do |r_id|
            memo[r_id] = c.time_zone
          end
        end

        rules.select do |rule|
          rule.is_occurring_at?(time, time_zones_by_rule_id[rule.id])
        end
      end

      private

      def self.checks_for_tag_match(strategy, tag_ids_by_rule_id)
        tag_ids_by_rule_id.values.inject(nil) do |memo, tag_ids|
          assocs = Flapjack::Data::Tag.intersect(:id => tag_ids).
            associations_for(:checks).values
          next memo if assocs.empty?

          checks = case strategy
          when 'all_tags'
            assocs.inject(Flapjack::Data::Check) do |c_memo, ca|
              c_memo = c_memo.intersect(:id => ca)
              c_memo
            end
          when 'any_tag'
            assocs.inject(nil) do |c_memo, ca|
              if c_memo.nil?
                Flapjack::Data::Check.intersect(:id => ca)
              else
                c_memo.union(:id => ca)
              end
            end
          when 'no_tag'
            assocs.inject(Flapjack::Data::Check) do |c_memo, ca|
              c_memo = c_memo.diff(:id => ca)
              c_memo
            end
          end

          memo = if memo.nil?
            Flapjack::Data::Check.intersect(:id => checks)
          else
            memo.union(:id => checks)
          end
          memo
        end
      end
    end
  end
end

