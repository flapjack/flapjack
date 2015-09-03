#!/usr/bin/env ruby

require 'set'

require 'active_support/inflector'
require 'active_support/core_ext/hash/slice'

require 'ice_cube'
require 'swagger/blocks'

require 'zermelo/records/redis'

require 'flapjack/utility'

require 'flapjack/data/extensions/short_name'
require 'flapjack/data/validators/id_validator'

require 'flapjack/data/time_restriction'

require 'flapjack/data/extensions/associations'
require 'flapjack/gateways/jsonapi/data/join_descriptor'
require 'flapjack/gateways/jsonapi/data/method_descriptor'

module Flapjack
  module Data
    class Rule

      STRATEGIES = ['global', 'any_tag', 'all_tags']

      extend Flapjack::Utility

      include Zermelo::Records::RedisSet
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false
      include Swagger::Blocks

      include Flapjack::Data::Extensions::Associations
      include Flapjack::Data::Extensions::ShortName

      # I've removed regex_* properties as they encourage loose binding against
      # check names, which may change. Do client-side grouping and create a tag!

      define_attributes :name => :string,
                        :blackhole => :boolean,
                        :strategy => :string,
                        :conditions_list => :string,
                        :time_restrictions_json => :string,
                        :has_media => :boolean,
                        :has_tags => :boolean

      index_by :name, :blackhole, :strategy, :conditions_list, :has_media, :has_tags

      validates_with Flapjack::Data::Validators::IdValidator

      validates :blackhole, :inclusion => {:in => [true, false]}
      validates :strategy, :inclusion => {:in => self::STRATEGIES}

      validates_each :time_restrictions_json do |record, att, value|
        unless value.nil?
          restrictions = Flapjack.load_json(value)
          case restrictions
          when Enumerable
            record.errors.add(att, 'are invalid') if restrictions.any? {|tr|
              !prepare_time_restriction(tr)
            }
          else
            record.errors.add(att, 'must contain a serialized Enumerable')
          end
        end
      end

      belongs_to :contact, :class_name => 'Flapjack::Data::Contact',
        :inverse_of => :rules

      has_and_belongs_to_many :media, :class_name => 'Flapjack::Data::Medium',
        :inverse_of => :rules, :after_add => :media_added,
        :after_remove => :media_removed

      has_and_belongs_to_many :tags, :class_name => 'Flapjack::Data::Tag',
        :inverse_of => :rules, :after_add => :tags_added,
        :after_remove => :tags_removed

      def initialize(attributes = {})
        super
        send(:"attribute=", 'has_media', false)
        send(:"attribute=", 'has_tags', false)
      end

      # TODO handle JSON exception
      def time_restrictions
        if self.time_restrictions_json.nil?
          @time_restrictions = nil
          return
        end
        @time_restrictions ||= Flapjack.load_json(self.time_restrictions_json)
      end

      def time_restrictions=(restrictions)
        @time_restrictions = restrictions
        self.time_restrictions_json = restrictions.nil? ? nil : Flapjack.dump_json(restrictions)
      end

      # nil time_restrictions matches
      # times (start, end) within time restrictions will have any UTC offset removed and will be
      # considered to be in the timezone of the contact
      def is_occurring_at?(time, timezone)
        return true if self.time_restrictions.nil? || self.time_restrictions.empty?

        user_time = time.in_time_zone(timezone)

        self.time_restrictions.any? do |tr|
          # add contact's timezone to the time restriction schedule
          schedule = self.class.time_restriction_to_icecube_schedule(tr, timezone)
          !schedule.nil? && schedule.occurring_at?(user_time)
        end
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

      def self.tags_added(rule_id, *t_ids)
        rule = self.find_by_id!(rule_id)
        rule.has_tags = true
        rule.save!
      end

      def self.tags_removed(rule_id, *t_ids)
        rule = self.find_by_id!(rule_id)
        rule.has_tags = rule.tags.empty?
        rule.save!
      end

      # called by medium.checks
      # no global rules in the passed rule data
      # rule_ids will be all acceptors
      # (blackhole == false) or all rejectors (blackhole == true)
      def self.matching_checks(rule_ids)
        m_checks = ['all_tags', 'any_tag'].inject(nil) do |memo, strategy|
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

        matching_ids = self.apply_time_restrictions(contact_rules, time).
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

        matching_ids = apply_time_restrictions(media_rules, time).
          map(&:id)

        self.intersect(:id => matching_ids).
          associated_ids_for(:media).values.reduce(Set.new, :|)
      end

      # NB: ice_cube doesn't have much rule data validation, and has
      # problems with infinite loops if the data can't logically match; see
      #   https://github.com/seejohnrun/ice_cube/issues/127 &
      #   https://github.com/seejohnrun/ice_cube/issues/137
      # We may want to consider some sort of timeout-based check around
      # anything that could fall into that.
      #
      # We don't want to replicate IceCube's from_hash behaviour here,
      # but we do need to apply some sanity checking on the passed data.
      def self.time_restriction_to_icecube_schedule(tr, timezone)
        return if tr.nil? || !tr.is_a?(Hash) ||
          timezone.nil? || !timezone.is_a?(ActiveSupport::TimeZone)

        tr = prepare_time_restriction(tr, timezone)
        return if tr.nil?

        IceCube::Schedule.from_hash(tr)
      end

      swagger_schema :Rule do
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
        property :strategy do
          key :type, :string
          key :enum, Flapjack::Data::Rule::STRATEGIES
        end
        property :conditions_list do
          key :type, :string
        end
        property :time_restrictions do
          key :type, :array
          items do
            key :"$ref", :TimeRestrictions
          end
        end
        property :relationships do
          key :"$ref", :RuleLinks
        end
      end

      swagger_schema :RuleLinks do
        key :required, [:self, :contact, :media, :tags]
        property :self do
          key :type, :string
          key :format, :url
        end
        property :contact do
          key :type, :string
          key :format, :url
        end
        property :media do
          key :type, :string
          key :format, :url
        end
        property :tags do
          key :type, :string
          key :format, :url
        end
      end

      swagger_schema :RuleCreate do
        key :required, [:type]
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
        property :strategy do
          key :type, :string
          key :enum, Flapjack::Data::Rule::STRATEGIES
        end
        property :conditions_list do
          key :type, :string
        end
        property :time_restrictions do
          key :type, :array
          items do
            key :"$ref", :TimeRestrictions
          end
        end
        property :relationships do
          key :"$ref", :RuleChangeLinks
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
        property :stratgey do
          key :type, :string
          key :enum, Flapjack::Data::Rule::STRATEGIES
        end
        property :conditions_list do
          key :type, :string
        end
        property :time_restrictions do
          key :type, :array
          items do
            key :"$ref", :TimeRestrictions
          end
        end
        property :relationships do
          key :"$ref", :RuleChangeLinks
        end
      end

      swagger_schema :RuleChangeLinks do
        property :contact do
          key :"$ref", :jsonapi_ContactLinkage
        end
        property :media do
          key :"$ref", :jsonapi_MediaLinkage
        end
        property :tags do
          key :"$ref", :jsonapi_TagsLinkage
        end
      end

      def self.jsonapi_methods
        @jsonapi_methods ||= {
          :post => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:name, :blackhole, :strategy, :conditions_list, :time_restrictions]
          ),
          :get => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:name, :blackhole, :strategy, :conditions_list, :time_restrictions]
          ),
          :patch => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:name, :blackhole, :strategy, :conditions_list, :time_restrictions]
          ),
          :delete => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
          )
        }
      end

      def self.jsonapi_associations
        if @jsonapi_associations.nil?
          @jsonapi_associations = {
            :contact => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :post => true, :get => true,
              :number => :singular, :link => true, :includable => true
            ),
            :media => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :post => true, :get => true, :patch => true, :delete => true,
              :number => :multiple, :link => true, :includable => true
            ),
            :tags => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :post => true, :get => true, :patch => true, :delete => true,
              :number => :multiple, :link => true, :includable => true
            )
          }
          populate_association_data(@jsonapi_associations)
        end
        @jsonapi_associations
      end

      protected

      def self.apply_time_restrictions(rules, time)
        # filter the rules by time restrictions
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
        tag_ids_by_rule_id.inject(nil) do |memo, (rule_id, tag_ids)|
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
          end

          memo = if memo.nil?
            Flapjack::Data::Check.intersect(:id => checks)
          else
            memo.union(:id => checks)
          end
          memo
        end
      end

      def self.prepare_time_restriction(time_restriction, timezone = nil)
        # this will hand back a 'deep' copy
        tr = symbolize(time_restriction)

        parsed_time = proc {|tr, field|
          if t = tr.delete(field)
            t = t.dup
            t = t[:time] if t.is_a?(Hash)

            if t.is_a?(Time)
              t
            else
              begin; (timezone || Time).parse(t); rescue ArgumentError; nil; end
            end
          else
            nil
          end
        }

        start_time = parsed_time.call(tr, :start_date) || parsed_time.call(tr, :start_time)
        end_time   = parsed_time.call(tr, :end_date) || parsed_time.call(tr, :end_time)

        return unless start_time && end_time

        tr[:start_time] = timezone ?
                            {:time => start_time, :zone => timezone.name} :
                            start_time

        tr[:end_time]   = timezone ?
                            {:time => end_time, :zone => timezone.name} :
                            end_time

        tr[:duration]   = end_time - start_time

        # check that rrule types are valid IceCube rule types
        return unless tr[:rrules].is_a?(Array) &&
          tr[:rrules].all? {|rr| rr.is_a?(Hash)} &&
          (tr[:rrules].map {|rr| rr[:rule_type]} -
           ['Daily', 'Hourly', 'Minutely', 'Monthly', 'Secondly',
            'Weekly', 'Yearly']).empty?

        # rewrite Weekly to IceCube::WeeklyRule, etc
        tr[:rrules].each {|rrule|
          rrule[:rule_type] = "IceCube::#{rrule[:rule_type]}Rule"
        }

        # exrules is deprecated in latest ice_cube, but may be stored in data
        # serialised from earlier versions of the gem
        # ( https://github.com/flapjack/flapjack/issues/715 )
        tr.delete(:exrules)

        # TODO does this need to check classes for the following values?
        # "validations": {
        #   "day": [1,2,3,4,5]
        # },
        # "interval": 1,
        # "week_start": 0

        tr
      end
    end
  end
end

