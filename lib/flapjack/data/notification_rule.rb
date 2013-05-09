#!/usr/bin/env ruby

require 'yajl/json_gem'
require 'active_support/time'
require 'ice_cube'
require 'flapjack/utility'

module Flapjack
  module Data
    class NotificationRule

      extend Flapjack::Utility

      attr_accessor :id, :contact_id, :entities, :entity_tags, :time_restrictions,
        :warning_media, :critical_media, :warning_blackhole, :critical_blackhole

      def self.exists_with_id?(rule_id, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        raise "No id value passed" unless not (rule_id.nil? || rule_id == '')
        logger   = options[:logger]
        redis.exists("notification_rule:#{rule_id}")
      end

      def self.find_by_id(rule_id, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        raise "No id value passed" unless not (rule_id.nil? || rule_id == '')
        logger   = options[:logger]

        # sanity check
        return unless redis.exists("notification_rule:#{rule_id}")

        self.new({:id => rule_id.to_s}, {:redis => redis})
      end

      # replacing save! etc
      def self.add(rule_data, options = {})
        raise "Redis connection not set" unless redis = options[:redis]

        rule_id = SecureRandom.uuid
        self.add_or_update(rule_data.merge(:id => rule_id), :redis => redis)
        self.find_by_id(rule_id, :redis => redis)
      end

      def update(rule_data)
        return false unless self.class.add_or_update(rule_data.merge(:id => @id),
          :redis => @redis)
        refresh
        true
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

      def to_json(*args)
        self.class.hashify(:id, :contact_id, :entity_tags, :entities,
            :time_restrictions, :warning_media, :critical_media,
            :warning_blackhole, :critical_blackhole) {|k|
          [k, self.send(k)]
        }.to_json
      end

      # tags or entity names match?
      # nil @entity_tags and nil @entities matches
      def match_entity?(event)
        # TODO: return true if event's entity tags match entity tag list on the rule
        ((@entity_tags.nil? || @entity_tags.empty?) && (@entities.nil? || @entities.empty?)) ||
         (@entities.include?(event.split(':').first))
      end

      def blackhole?(severity)
        ('warning'.eql?(severity.downcase) && @warning_blackhole) ||
          ('critical'.eql?(severity.downcase) && @critical_blackhole)
      end

      def media_for_severity(severity)
        case severity
        when 'warning'
          @warning_media
        when 'critical'
          @critical_media
        end
      end

    private

      def initialize(rule_data, opts = {})
        @redis  ||= opts[:redis]
        raise "a redis connection must be supplied" unless @redis
        @logger   = opts[:logger]
        @id       = rule_data[:id]
        refresh
      end

      def self.add_or_update(rule_data, options = {})
        redis = options[:redis]
        raise "a redis connection must be supplied" unless redis

        return unless self.validate_data(rule_data, options)

        # whitelisting fields, rather than passing through submitted data directly
        json_rule_data = {
          :id                 => rule_data[:id].to_s,
          :contact_id         => rule_data[:contact_id].to_s,
          :entities           => Yajl::Encoder.encode(rule_data[:entities]),
          :entity_tags        => Yajl::Encoder.encode(rule_data[:entity_tags]),
          :time_restrictions  => Yajl::Encoder.encode(rule_data[:time_restrictions]),
          :warning_media      => Yajl::Encoder.encode(rule_data[:warning_media]),
          :critical_media     => Yajl::Encoder.encode(rule_data[:critical_media]),
          :warning_blackhole  => rule_data[:warning_blackhole],
          :critical_blackhole => rule_data[:critical_blackhole],
        }

        redis.sadd("contact_notification_rules:#{json_rule_data[:contact_id]}",
                   json_rule_data[:id])
        redis.hmset("notification_rule:#{json_rule_data[:id]}",
                    *json_rule_data.flatten)
        true
      end

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

      def self.validate_data(d, options = {})
        # hash with validation => error_message
        validations = {proc { d.has_key?(:id) } =>
                       "id not set",

                       proc { d.has_key?(:entities) &&
                              d[:entities].is_a?(Array) &&
                              d[:entities].all? {|e| e.is_a?(String)} } =>
                       "entities must be a list of strings",

                       proc { d.has_key?(:entity_tags) &&
                              d[:entity_tags].is_a?(Array) &&
                              d[:entity_tags].all? {|et| et.is_a?(String)}} =>
                       "entity_tags must be a list of strings",

                       proc { (d.has_key?(:entities) &&
                               d[:entities].is_a?(Array) &&
                               (d[:entities].size > 0)) ||
                              (d.has_key?(:entity_tags) &&
                               d[:entity_tags].is_a?(Array) &&
                               (d[:entity_tags].size > 0)) } =>
                       "entities or entity tags must have at least one value",

                       proc { d.has_key?(:time_restrictions) &&
                              d[:time_restrictions].all? {|tr|
                                !!prepare_time_restriction(symbolize(tr))
                              }
                            } =>
                       "time restrictions are invalid",

                       # TODO should the media types be checked against a whitelist?
                       proc { d.has_key?(:warning_media) &&
                              d[:warning_media].is_a?(Array) &&
                              d[:warning_media].all? {|et| et.is_a?(String)}} =>
                       "warning_media must be a list of strings",

                       proc { d.has_key?(:critical_media) &&
                              d[:critical_media].is_a?(Array) &&
                              d[:critical_media].all? {|et| et.is_a?(String)}} =>
                       "critical_media must be a list of strings",

                       proc { d.has_key?(:warning_blackhole) &&
                              [TrueClass, FalseClass].include?(d[:warning_blackhole].class) } =>
                       "warning_blackhole must be true or false",

                       proc { d.has_key?(:critical_blackhole) &&
                              [TrueClass, FalseClass].include?(d[:critical_blackhole].class) } =>
                       "critical_blackhole must be true or false",
                      }

        errors = validations.keys.inject([]) {|ret,vk|
          ret << "Rule #{validations[vk]}" unless vk.call
          ret
        }

        return true if errors.empty?

        if logger = options[:logger]
          error_str = errors.join(", ")
          logger.info "validation error: #{error_str}"
        end
        false
      end

      def refresh
        rule_data = @redis.hgetall("notification_rule:#{@id}")

        @contact_id         = rule_data['contact_id']
        @entity_tags        = Yajl::Parser.parse(rule_data['entity_tags'] || '')
        @entities           = Yajl::Parser.parse(rule_data['entities'] || '')
        @time_restrictions  = Yajl::Parser.parse(rule_data['time_restrictions'] || '')
        @warning_media      = Yajl::Parser.parse(rule_data['warning_media'] || '')
        @critical_media     = Yajl::Parser.parse(rule_data['critical_media'] || '')
        @warning_blackhole  = ((rule_data['warning_blackhole'] || 'false').downcase == 'true')
        @critical_blackhole = ((rule_data['critical_blackhole'] || 'false').downcase == 'true')
      end

    end
  end
end

