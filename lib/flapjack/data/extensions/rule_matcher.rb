#!/usr/bin/env ruby

require 'active_support/concern'
require 'active_support/inflector'
require 'active_support/core_ext/hash/slice'

require 'sinatra/base'

require 'flapjack/gateways/jsonapi/data/join_descriptor'
require 'flapjack/gateways/jsonapi/data/method_descriptor'

module Flapjack
  module Data
    module Extensions
      module RuleMatcher

        extend ActiveSupport::Concern

        module ClassMethods

          def has_some_media(rule_id, *m)
            rule = Flapjack::Data::Rule.find_by_id!(rule_id)
            rule.has_media = true
            rule.save!
          end

          def has_no_media(rule_id, *m)
            rule = Flapjack::Data::Rule.find_by_id!(rule_id)
            return unless rule.media.empty?
            rule.has_media = false
            rule.save!
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
          def time_restriction_to_icecube_schedule(tr, timezone)
            return if tr.nil? || !tr.is_a?(Hash) ||
              timezone.nil? || !timezone.is_a?(ActiveSupport::TimeZone)

            tr = prepare_time_restriction(tr, timezone)
            return if tr.nil?

            IceCube::Schedule.from_hash(tr)
          end

          private

          def prepare_time_restriction(time_restriction, timezone = nil)
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

        included do
          # I've removed regex_* properties as they encourage loose binding against
          # names, which may change. Do client-side grouping and create a tag!

          define_attributes :name => :string,
                            :all => :boolean,
                            :conditions_list => :string,
                            :time_restrictions_json => :string,
                            :has_media => :boolean,
                            :has_tags => :boolean

          index_by :name, :all, :conditions_list, :has_media, :has_tags

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

        end

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

      end
    end
  end
end
