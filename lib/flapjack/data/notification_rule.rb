#!/usr/bin/env ruby

require 'oj'
require 'active_support/time'
require 'ice_cube'
require 'flapjack/utility'
require 'flapjack/data/tag_set'

module Flapjack
  module Data
    class NotificationRule

      extend Flapjack::Utility

      attr_accessor :id, :contact_id, :entities, :tags, :time_restrictions,
        :unknown_media, :warning_media, :critical_media,
        :unknown_blackhole, :warning_blackhole, :critical_blackhole

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

        if rule_data[:id] && self.find_by_id(rule_data[:id], :redis => redis)
          errors = ["a notification rule already exists with id '#{rule_data[:id]}'"]
          return errors
        end
        rule_id = rule_data[:id] || SecureRandom.uuid
        errors = self.add_or_update(rule_data.merge(:id => rule_id), options)
        return errors unless errors.nil? || errors.empty?
        self.find_by_id(rule_id, :redis => redis)
      end

      def update(rule_data, opts = {})
        errors = self.class.add_or_update({:contact_id => @contact_id}.merge(rule_data.merge(:id => @id)),
          :redis => @redis, :logger => opts[:logger])
        return errors unless errors.nil? || errors.empty?
        refresh
        nil
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
        self.class.hashify(:id, :contact_id, :tags, :entities,
            :time_restrictions, :unknown_media, :warning_media, :critical_media,
            :unknown_blackhole, :warning_blackhole, :critical_blackhole) {|k|
          [k, self.send(k)]
        }.to_json
      end

      # entity names match?
      def match_entity?(event_id)
        return false unless @entities
        @entities.include?(event_id.split(':').first)
      end

      # tags match?
      def match_tags?(event_tags)
        return false unless @tags && @tags.length > 0
        matches = 0
        rule_uses_regex = false
        event_tags.each do |event_tag|
          @tags.each do |tag|
            if tag.start_with?('regex:')
              if /^#{tag.split('regex:').last}$/ === event_tag
                matches += 1
                rule_uses_regex = true
              end
            end
          end
        end
        if rule_uses_regex
          matches >= @tags.length
        else
          @tags.subset?(event_tags)
        end
      end

      def blackhole?(severity)
        ('unknown'.eql?(severity.downcase) && @unknown_blackhole) ||
          ('warning'.eql?(severity.downcase) && @warning_blackhole) ||
          ('critical'.eql?(severity.downcase) && @critical_blackhole)
      end

      def media_for_severity(severity)
        case severity
        when 'unknown'
          @unknown_media
        when 'warning'
          @warning_media
        when 'critical'
          @critical_media
        end
      end

      def is_specific?
        (!@entities.nil? && !@entities.empty?) ||
          (!@tags.nil? && !@tags.empty?)
      end

    private

      def initialize(rule_data, opts = {})
        @redis  ||= opts[:redis]
        raise "a redis connection must be supplied" unless @redis
        @logger   = opts[:logger]
        @id       = rule_data[:id]
        refresh
      end

      def self.prevalidate_data(rule_data, options = {})
        errors = self.validate_data(preen(rule_data), options.merge(:id_not_required => true))
      end

      def self.preen(rule_data)
        # make some assumptions about the incoming data
        rule_data[:unknown_blackhole]  = rule_data[:unknown_blackhole] || false
        rule_data[:warning_blackhole]  = rule_data[:warning_blackhole] || false
        rule_data[:critical_blackhole] = rule_data[:critical_blackhole] || false
        if rule_data[:tags].is_a?(Array)
          rule_data[:tags] = Flapjack::Data::TagSet.new(rule_data[:tags])
        end
        rule_data
      end

      def self.add_or_update(rule_data, options = {})
        redis = options[:redis]
        raise "a redis connection must be supplied" unless redis
        logger = options[:logger]

        rule_data = preen(rule_data)
        errors = self.validate_data(rule_data, options)
        return errors unless errors.nil? || errors.empty?

        # whitelisting fields, rather than passing through submitted data directly
        tag_data = rule_data[:tags].is_a?(Set) ? rule_data[:tags].to_a : nil
        json_rule_data = {
          :id                 => rule_data[:id].to_s,
          :contact_id         => rule_data[:contact_id].to_s,
          :entities           => Oj.dump(rule_data[:entities]),
          :tags               => Oj.dump(tag_data),
          :time_restrictions  => Oj.dump(rule_data[:time_restrictions], :mode => :compat),
          :unknown_media      => Oj.dump(rule_data[:unknown_media]),
          :warning_media      => Oj.dump(rule_data[:warning_media]),
          :critical_media     => Oj.dump(rule_data[:critical_media]),
          :unknown_blackhole  => rule_data[:unknown_blackhole],
          :warning_blackhole  => rule_data[:warning_blackhole],
          :critical_blackhole => rule_data[:critical_blackhole],
        }
        logger.debug("NotificationRule#add_or_update json_rule_data: #{json_rule_data.inspect}") if logger

        redis.sadd("contact_notification_rules:#{json_rule_data[:contact_id]}",
                   json_rule_data[:id])
        redis.hmset("notification_rule:#{json_rule_data[:id]}",
                    *json_rule_data.flatten)
        nil
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

      VALIDATION_PROCS = {
        proc {|d| !d.has_key?(:entities) ||
               ( d[:entities].nil? ||
                 d[:entities].is_a?(Array) &&
                 d[:entities].all? {|e| e.is_a?(String)} ) } =>
        "entities must be a list of strings",

        proc {|d| !d.has_key?(:tags) ||
               ( d[:tags].nil? ||
                 d[:tags].is_a?(Flapjack::Data::TagSet) &&
                 d[:tags].all? {|et| et.is_a?(String)} ) } =>
        "tags must be a tag_set of strings",

        proc {|d| !d.has_key?(:time_restrictions) ||
               ( d[:time_restrictions].nil? ||
                 d[:time_restrictions].all? {|tr|
                   !!prepare_time_restriction(symbolize(tr))
                 } )
             } =>
        "time restrictions are invalid",

        # TODO should the media types be checked against a whitelist?
        proc {|d| !d.has_key?(:unknown_media) ||
               ( d[:unknown_media].nil? ||
                 d[:unknown_media].is_a?(Array) &&
                 d[:unknown_media].all? {|et| et.is_a?(String)} ) } =>
        "unknown_media must be a list of strings",

        proc {|d| !d.has_key?(:warning_media) ||
               ( d[:warning_media].nil? ||
                 d[:warning_media].is_a?(Array) &&
                 d[:warning_media].all? {|et| et.is_a?(String)} ) } =>
        "warning_media must be a list of strings",

        proc {|d| !d.has_key?(:critical_media) ||
               ( d[:critical_media].nil? ||
                 d[:critical_media].is_a?(Array) &&
                 d[:critical_media].all? {|et| et.is_a?(String)} ) } =>
        "critical_media must be a list of strings",

        proc {|d| !d.has_key?(:unknown_blackhole) ||
               [TrueClass, FalseClass].include?(d[:unknown_blackhole].class) } =>
        "unknown_blackhole must be true or false",

        proc {|d| !d.has_key?(:warning_blackhole) ||
               [TrueClass, FalseClass].include?(d[:warning_blackhole].class) } =>
        "warning_blackhole must be true or false",

        proc {|d| !d.has_key?(:critical_blackhole) ||
               [TrueClass, FalseClass].include?(d[:critical_blackhole].class) } =>
        "critical_blackhole must be true or false",
      }

      def self.validate_data(d, options = {})
        id_not_required = !!options[:id_not_required]
        # hash with validation => error_message
        validations = {}
        validations.merge!({ proc { d.has_key?(:id) } => "id not set"}) unless id_not_required
        validations.merge!(VALIDATION_PROCS)

        errors = validations.keys.inject([]) {|ret,vk|
          ret << "Rule #{validations[vk]}" unless vk.call(d)
          ret
        }

        return if errors.empty?

        if logger = options[:logger]
          error_str = errors.join(", ")
          logger.info "validation error: #{error_str}"
          logger.debug "rule failing validations: #{d.inspect}"
        end
        errors
      end

      def refresh
        rule_data = @redis.hgetall("notification_rule:#{@id}")

        @contact_id         = rule_data['contact_id']
        tags                = Oj.load(rule_data['tags'] || '')
        @tags               = tags ? Flapjack::Data::TagSet.new(tags) : nil
        @entities           = Oj.load(rule_data['entities'] || '')
        @time_restrictions  = Oj.load(rule_data['time_restrictions'] || '')
        @unknown_media      = Oj.load(rule_data['unknown_media'] || '')
        @warning_media      = Oj.load(rule_data['warning_media'] || '')
        @critical_media     = Oj.load(rule_data['critical_media'] || '')
        @unknown_blackhole  = ((rule_data['unknown_blackhole'] || 'false').downcase == 'true')
        @warning_blackhole  = ((rule_data['warning_blackhole'] || 'false').downcase == 'true')
        @critical_blackhole = ((rule_data['critical_blackhole'] || 'false').downcase == 'true')
      end

    end
  end
end

