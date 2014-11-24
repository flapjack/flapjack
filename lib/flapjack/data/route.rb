#!/usr/bin/env ruby

require 'active_support/time'
require 'ice_cube'

require 'flapjack/utility'

require 'sandstorm/records/redis_record'

require 'flapjack/data/validators/id_validator'

require 'flapjack/data/check_state'

module Flapjack
  module Data
    class Route

      extend Flapjack::Utility

      include Sandstorm::Records::RedisRecord

      # TODO change to Flapjack::Data::State class
      define_attributes :state => :string,
                        :drop => :boolean,
                        :time_restrictions_json => :string

      index_by :state, :drop

      belongs_to :rule, :class_name => 'Flapjack::Data::Rule',
        :inverse_of => :routes

      has_and_belongs_to_many :media, :class_name => 'Flapjack::Data::Medium',
        :inverse_of => :routes

      validate :state, :presence => true,
        :inclusion => { :in => Flapjack::Data::CheckState.failing_states }

      validates_with Flapjack::Data::Validators::IdValidator

      # TODO validate that rule and media belong to the same contact

      # TODO drop should not be exposed in the API, set it when media empty
      #   and remove if media not empty

      # before_destroy :correct_alerting_media
      # def correct_alerting_media
      #   self.class.lock(Flapjack::Data::Medium, Flapjack::Data::Check) do

      #     self.media.each do |medium|
      #       medium.alerting_checks.each do |check|

      #         # if this is the only route that links the media to that check,
      #         # remove from the set of alerting_checks for that media; will
      #         # need to use current check state to limit route set as well

      #       end

      #     end

      #   end
      # end

      def self.as_jsonapi(options = {})
        routes = options[:resources]
        return [] if routes.nil? || routes.empty?

        fields = options[:fields]
        unwrap = options[:unwrap]
        # incl   = options[:include]

        whitelist = [:id, :state, :time_restrictions]

        jsonapi_fields = if fields.nil?
          whitelist
        else
          Set.new(fields).add(:id).keep_if {|f| whitelist.include?(f) }.to_a
        end

        route_ids = routes.map(&:id)
        rule_ids  = Flapjack::Data::Route.intersect(:id => route_ids).
                      associated_ids_for(:rule)
        media_ids = Flapjack::Data::Route.intersect(:id => route_ids).
                      associated_ids_for(:media)

        data = routes.collect do |route|
          route.as_json(:only => jsonapi_fields).merge(:links => {
            :rule  => rule_ids[route.id],
            :media => media_ids[route.id]
          })
        end

        return data unless (data.size == 1) && unwrap
        data.first
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
        return unless !tr.nil? && tr.is_a?(Hash)
        return if timezone.nil? && !timezone.is_a?(ActiveSupport::TimeZone)
        return unless tr = prepare_time_restriction(tr, timezone)

        IceCube::Schedule.from_hash(tr)
      end

      # nil time_restrictions matches
      # times (start, end) within time restrictions will have any UTC offset removed and will be
      # considered to be in the timezone of the contact
      def is_occurring_now?(timezone)
        return true if self.time_restrictions.nil? || self.time_restrictions.empty?

        usertime = timezone.now

        self.time_restrictions.any? do |tr|
          # add contact's timezone to the time restriction schedule
          schedule = self.class.time_restriction_to_icecube_schedule(tr, timezone)
          schedule && schedule.occurring_at?(usertime)
        end
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