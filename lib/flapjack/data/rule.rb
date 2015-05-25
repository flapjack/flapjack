#!/usr/bin/env ruby

require 'set'

require 'ice_cube'
require 'swagger/blocks'

require 'zermelo/records/redis'

require 'flapjack/data/validators/id_validator'
require 'flapjack/data/route'
require 'flapjack/data/time_restriction'

require 'flapjack/gateways/jsonapi/data/associations'
require 'flapjack/gateways/jsonapi/data/join_descriptor'
require 'flapjack/gateways/jsonapi/data/method_descriptor'

module Flapjack
  module Data
    class Rule

      extend Flapjack::Utility

      include Zermelo::Records::Redis
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false
      include Flapjack::Gateways::JSONAPI::Data::Associations
      include Swagger::Blocks

      # I've removed regex_* properties as they encourage loose binding against
      # names, which may change. Do client-side grouping and create a tag!

      define_attributes :conditions_list => :string,
                        :has_media => :boolean,
                        :has_tags => :boolean,
                        :time_restrictions_json => :string

      index_by :conditions_list, :has_media, :has_tags

      belongs_to :contact, :class_name => 'Flapjack::Data::Contact',
        :inverse_of => :rules

      has_and_belongs_to_many :media, :class_name => 'Flapjack::Data::Medium',
        :inverse_of => :rules, :after_add => :has_some_media,
        :after_remove => :has_no_media

      before_destroy :remove_routes

      def remove_routes
        self.routes.destroy_all
      end

      def has_some_media(*m)
        self.has_media = true
        self.save
      end

      def has_no_media(*m)
        return unless self.media.empty?
        self.has_media = false
        self.save
      end

      has_and_belongs_to_many :tags, :class_name => 'Flapjack::Data::Tag',
        :inverse_of => :rules, :after_add => :tags_added,
        :after_remove => :tags_removed,
        :related_class_names => ['Flapjack::Data::Contact',
          'Flapjack::Data::Check', 'Flapjack::Data::Route']

      # NB when a rule is created, recalculate_routes should be called
      # by the creating code if no tags are being added. FIXME -- maybe do
      # from an after_create hook just to be safe?
      #
      # TODO on change to conditions_list, update value for all routes
      def recalculate_routes
        self.routes.destroy_all

        co = self.contact
        contact_id = co.nil? ? nil : co.id

        route_for_check = proc {|c|
          route = Flapjack::Data::Route.new(:is_alerting => false,
            :conditions_list => self.conditions_list)
          route.save

          self.routes << route
          c.routes << route
          c.contacts.add_ids(contact_id) unless contact_id.nil?
        }

        if self.has_tags
          # find all checks matching these tags -- FIXME there may be a more
          # Zermelo-idiomatic way to do this

          check_ids = self.tags.associated_ids_for(:checks).values.reduce(:&)

          unless check_ids.empty?
            Flapjack::Data::Check.intersect(:id => check_ids).each do |check|
              route_for_check.call(check)
            end
          end
        else
          # create routes between this rule and all checks
          Flapjack::Data::Check.each {|check| route_for_check.call(check) }
        end
      end

      def tags_added(*t)
        self.has_tags = true
        recalculate_routes
        self.save
      end

      def tag_removed(*t)
        self.has_tags = self.tags.empty?
        recalculate_routes
        self.save
      end

      has_many :routes, :class_name => 'Flapjack::Data::Route',
        :inverse_of => :rule

      def initialize(attributes = {})
        super
        send(:"attribute=", 'has_media', false)
        send(:"attribute=", 'has_tags', false)
      end

      validates_with Flapjack::Data::Validators::IdValidator

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

      def conditions
        return if self.conditions_list.nil?
        @conditions ||= self.conditions_list.
          sub(/^\|/, '').sub(/\|$/, '').split('|').each_with_object  do |c, memo|

          cond = Flapjack::Data::Condition.for_name(c)
          memo << cond unless cond.nil?
        end
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

      def self.jsonapi_type
        self.name.demodulize.underscore
      end

      swagger_schema :Rule do
        key :required, [:id, :type]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::Rule.jsonapi_type.downcase]
        end
        # property :time_restrictions do
        #   key :type, :array
        #   items do
        #     key :"$ref", :TimeRestrictions
        #   end
        # end
        property :links do
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
          key :enum, [Flapjack::Data::Rule.jsonapi_type.downcase]
        end
        # property :time_restrictions do
        #   key :type, :array
        #   items do
        #     key :"$ref", :TimeRestrictions
        #   end
        # end
        property :links do
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
          key :enum, [Flapjack::Data::Rule.jsonapi_type.downcase]
        end
        # property :time_restrictions do
        #   key :type, :array
        #   items do
        #     key :"$ref", :TimeRestrictions
        #   end
        # end
        property :links do
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
            :attributes => [] # [:time_restrictions]
          ),
          :get => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:conditions_list] # [:time_restrictions]
          ),
          :patch => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [] # [:time_restrictions]
          ),
          :delete => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :lock_klasses => [Flapjack::Data::Route, Flapjack::Data::Check]
          )
        }
      end

      def self.jsonapi_associations
        @jsonapi_associations ||= {
          :contact => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
            :writable => true, :number => :singular,
            :link => true, :include => true
          ),
          :media => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
            :writable => true, :number => :multiple,
            :link => true, :include => true
          ),
          :tags => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
            :writable => true, :number => :multiple,
            :link => true, :include => true
          )
        }
      end

      private

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

