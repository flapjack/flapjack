#!/usr/bin/env ruby

require 'set'

require 'active_support/time'
require 'ice_cube'

require 'flapjack/utility'

require 'sandstorm/record'

module Flapjack
  module Data
    class NotificationRule

      extend Flapjack::Utility

      include Sandstorm::Record

      define_attributes :entities                => :set,
                        :tags                    => :set,
                        :time_restrictions_json  => :string

      belongs_to :contact, :class_name => 'Flapjack::Data::Contact'

      has_many :states, :class_name => 'Flapjack::Data::NotificationRuleState'

      validates_each :entities, :tags, #, :unknown_media, :warning_media, :critical_media,
        :allow_blank => true do |record, att, value|
        if value.is_a?(Set) && value.any? {|vs| !vs.is_a?(String) }
          record.errors.add(att, 'must only contain strings')
        end
      end

      validates_each :time_restrictions_json do |record, att, value|
        unless value.nil?
          restrictions = JSON.parse(value)
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

      # TODO handle JSON exception
      def time_restrictions
        if self.time_restrictions_json.nil?
          @time_restrictions = nil
          return
        end
        @time_restrictions = JSON.parse(self.time_restrictions_json)
      end

      def time_restrictions=(restrictions)
        @time_restrictions = restrictions
        self.time_restrictions_json = restrictions.nil? ? nil : restrictions.to_json
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
        return unless !tr.nil? && tr.is_a?(Hash)
        return if timezone.nil? && !timezone.is_a?(ActiveSupport::TimeZone)
        return unless tr = prepare_time_restriction(tr, timezone)

        IceCube::Schedule.from_hash(tr)
      end

      # entity names match?
      def match_entity?(event_id)
        entities.present? && entities.include?(event_id.split(':').first)
      end

      # tags match?
      def match_tags?(event_tags)
        tags.present? && tags.subset?(event_tags)
      end

      def is_specific?
        entities.present? || tags.present?
      end

      # nil time_restrictions matches
      # times (start, end) within time restrictions will have any UTC offset removed and will be
      # considered to be in the timezone of the contact
      def is_occurring_now?(options = {})
        contact = options[:contact]
        def_tz = options[:default_timezone]

        return true if self.time_restrictions.nil? || self.time_restrictions.empty?

        timezone = contact.time_zone(:default => def_tz)
        usertime = timezone.now

        self.time_restrictions.any? do |tr|
          # add contact's timezone to the time restriction schedule
          schedule = Flapjack::Data::NotificationRule.
                       time_restriction_to_icecube_schedule(tr, timezone)
          schedule && schedule.occurring_at?(usertime)
        end
      end

    private

      def self.prepare_time_restriction(time_restriction, timezone = nil)
        # this will hand back a 'deep' copy
        tr = symbolize(time_restriction)

        return unless tr.has_key?(:start_time) && tr.has_key?(:end_time)

        parsed_time = proc {|t|
          if t.is_a?(Time)
            t
          else
            begin; (timezone || Time).parse(t); rescue ArgumentError; nil; end
          end
        }

        start_time = case tr[:start_time]
        when String, Time
          parsed_time.call(tr.delete(:start_time).dup)
        when Hash
          time_hash = tr.delete(:start_time).dup
          parsed_time.call(time_hash[:time])
        end

        end_time = case tr[:end_time]
        when String, Time
          parsed_time.call(tr.delete(:end_time).dup)
        when Hash
          time_hash = tr.delete(:end_time).dup
          parsed_time.call(time_hash[:time])
        end

        return unless start_time && end_time

        tr[:start_date] = timezone ?
                            {:time => start_time, :zone => timezone.name} :
                            start_time

        tr[:end_date]   = timezone ?
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

