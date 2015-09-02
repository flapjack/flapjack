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

          def media_added(rule_id, *m_ids)
            rule = self.find_by_id!(rule_id)
            rule.has_media = true
            rule.save!
          end

          def media_removed(rule_id, *m_ids)
            rule = self.find_by_id!(rejector_id)
            rule.has_media = rule.media.empty?
            rule.save!
          end

          def tags_added(rule_id, *t_ids)
            rule = self.find_by_id!(rule_id)
            rule.has_tags = true
            rule.save!
          end

          def tags_removed(rule_id, *t_ids)
            rule = self.find_by_id!(rule_id)
            rule.has_tags = rule.tags.empty?
            rule.save!
          end

          # called by medium.checks
          # no global rules in the passed rule data
          def matching_checks(rule_ids)
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

          # called by check.contacts
          def matching_contact_ids(rule_ids, opts = {})
            time = opts[:time] || Time.now
            contact_rules = self.intersect(:id => rule_ids)

            matching_rule_ids = self.apply_time_restrictions(contact_rules, time).
              map(&:id)

            self.intersect(:id => matching_rule_ids).
              associated_ids_for(:contact, :inversed => true).keys
          end

          # called by check.alerting_media
          def matching_media_ids(rule_ids, opts = {})
            time = opts[:time] || Time.now

            # if a rule has no media, it's irrelevant here
            media_rules = self.intersect(:id => rule_ids, :has_media => true)

            matching_rule_ids = apply_time_restrictions(media_rules, time).
              map(&:id)

            self.intersect(:id => matching_rule_ids).
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
          def time_restriction_to_icecube_schedule(tr, timezone)
            return if tr.nil? || !tr.is_a?(Hash) ||
              timezone.nil? || !timezone.is_a?(ActiveSupport::TimeZone)

            tr = prepare_time_restriction(tr, timezone)
            return if tr.nil?

            IceCube::Schedule.from_hash(tr)
          end

          protected

          def apply_time_restrictions(rules, time)
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

          def checks_for_tag_match(strategy, tag_ids_by_rule_id)
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
          # check names, which may change. Do client-side grouping and create a tag!

          define_attributes :name => :string,
                            :strategy => :string,
                            :conditions_list => :string,
                            :time_restrictions_json => :string,
                            :has_media => :boolean,
                            :has_tags => :boolean

          index_by :name, :strategy, :conditions_list, :has_media, :has_tags

          validates_with Flapjack::Data::Validators::IdValidator

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
