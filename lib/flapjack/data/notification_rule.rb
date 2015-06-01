#!/usr/bin/env ruby

require 'active_support/time'
require 'ice_cube'
require 'flapjack/utility'

module Flapjack
  module Data
    class NotificationRule

      extend Flapjack::Utility

      attr_accessor :id, :contact_id, :entities, :regex_entities, :tags, :regex_tags,
        :time_restrictions, :unknown_media, :warning_media, :critical_media,
        :unknown_blackhole, :warning_blackhole, :critical_blackhole

      def self.all(options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        redis.keys("contact_notification_rules:*").inject([]) do |memo, contact_key|
          redis.smembers(contact_key).each do |rule_id|
            ret = self.find_by_id(rule_id, :redis => redis)
            memo << ret unless ret.nil?
          end
          memo
        end
      end

      def self.exists_with_id?(rule_id, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        raise "No id value passed" unless not (rule_id.nil? || rule_id == '')
        redis.exists("notification_rule:#{rule_id}")
      end

      def self.find_by_id(rule_id, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        raise "No id value passed" unless not (rule_id.nil? || rule_id == '')

        # sanity check
        return unless redis.exists("notification_rule:#{rule_id}")

        self.new({:id => rule_id.to_s}, {:redis => redis})
      end

      def self.find_by_ids(rule_ids, options = {})
        raise "Redis connection not set" unless redis = options[:redis]

        rule_ids.map do |id|
          self.find_by_id(id, options)
        end
      end

      # replacing save! etc
      def self.add(rule_data, options = {})
        raise "Redis connection not set" unless redis = options[:redis]

        if rule_data[:id] && self.find_by_id(rule_data[:id], :redis => redis)
          errors = ["a notification rule already exists with id '#{rule_data[:id]}'"]
          return errors
        end
        rule_id = rule_data[:id] || SecureRandom.uuid

        errors = self.add_or_update(rule_data.merge(:id => rule_id), :redis => redis, :logger => options[:logger])
        return errors unless errors.nil? || errors.empty?

        self.find_by_id(rule_id, :redis => redis)
      end

      def update(update_data, opts = {})
        [:entities, :regex_entities, :tags, :regex_tags,
         :time_restrictions, :unknown_media, :warning_media, :critical_media,
         :unknown_blackhole, :warning_blackhole, :critical_blackhole].each do |update_key|

          next if update_data.has_key?(update_key)
          update_data[update_key] = self.send(update_key)
        end

        update_data.update(:id => @id, :contact_id => @contact_id)
        errors = self.class.add_or_update(update_data, :redis => @redis, :logger => opts[:logger])
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
      def self.time_restriction_to_icecube_schedule(tr, timezone, opts = {})
        return if tr.nil? || !tr.is_a?(Hash) ||
                  timezone.nil? || !timezone.is_a?(ActiveSupport::TimeZone)
        prepared_restrictions = prepare_time_restriction(tr, timezone)
        return if prepared_restrictions.nil?
        IceCube::Schedule.from_hash(prepared_restrictions)
      rescue ArgumentError => ae
        if logger = opts[:logger]
          logger.error "Couldn't parse rule data #{e.class}: #{e.message}"
          logger.error prepared_restrictions.inspect
          logger.error e.backtrace.join("\n")
        end
        nil
      end

      def to_jsonapi(opts = {})
        json_data = self.class.hashify(:id, :tags, :regex_tags, :entities, :regex_entities,
            :time_restrictions, :unknown_media, :warning_media, :critical_media,
            :unknown_blackhole, :warning_blackhole, :critical_blackhole) {|k|
          case k
          when :tags, :regex_tags
            [k.to_s, self.send(k).to_a.sort]
          else
            [k.to_s, self.send(k)]
          end
        }.merge('links' => {'contacts' => [self.contact_id]})

        Flapjack.dump_json(json_data)
      end

      # If the rule has any entities, then one of them must match the event's entity
      def match_entity?(event_id)
        return true unless @entities && @entities.length > 0
        event_entity = event_id.split(':').first
        @entities.include?(event_entity)
      end

      # If the rule has any regex_entities, then all of them must match the
      # event's entity
      def match_regex_entities?(event_id)
        return true unless @regex_entities && @regex_entities.length > 0
        event_entity = event_id.split(':').first
        matches = 0
        @regex_entities.each do |regex_entity|
          matches += 1 if /#{regex_entity}/ === event_entity
        end
        matches >= @regex_entities.length
      end

      # If the rule has any tags, then they must all be present in the
      # event's tags
      def match_tags?(event_tags)
        return true unless @tags && @tags.length > 0
        @tags.subset?(event_tags)
      end

      # If the rule has any regex_tags, then they must all match at least
      # one of the event's tags
      def match_regex_tags?(event_tags)
        return true unless @regex_tags && @regex_tags.length > 0
        matches = 0
        @regex_tags.each do |regex_tag|
          matches += 1 if event_tags.any? { |event_tag| /#{regex_tag}/ === event_tag }
        end
        matches >= @regex_tags.length
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
          (!@regex_entities.nil? && !@regex_entities.empty?) ||
          (!@tags.nil? && !@tags.empty?) ||
          (!@regex_tags.nil? && !@regex_tags.empty?)
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
          rule_data[:tags] = Set.new(rule_data[:tags])
        end
        if rule_data[:regex_tags].is_a?(Array)
          rule_data[:regex_tags] = Set.new(rule_data[:regex_tags])
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
        tag_data       = rule_data[:tags].is_a?(Set) ? rule_data[:tags].to_a : nil
        regex_tag_data = rule_data[:regex_tags].is_a?(Set) ? rule_data[:regex_tags].to_a : nil

        json_rule_data = {
          :id                 => rule_data[:id].to_s,
          :contact_id         => rule_data[:contact_id].to_s,
          :entities           => Flapjack.dump_json(rule_data[:entities]),
          :regex_entities     => Flapjack.dump_json(rule_data[:regex_entities]),
          :tags               => Flapjack.dump_json(tag_data),
          :regex_tags         => Flapjack.dump_json(regex_tag_data),
          :time_restrictions  => Flapjack.dump_json(rule_data[:time_restrictions]),
          :unknown_media      => Flapjack.dump_json(rule_data[:unknown_media]),
          :warning_media      => Flapjack.dump_json(rule_data[:warning_media]),
          :critical_media     => Flapjack.dump_json(rule_data[:critical_media]),
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

        return unless (tr.has_key?(:start_time) || tr.has_key?(:start_date)) &&
          (tr.has_key?(:end_time) || tr.has_key?(:end_date))

        # exrules is deprecated in latest ice_cube, but may be stored in data
        # serialised from earlier versions of the gem
        # ( https://github.com/flapjack/flapjack/issues/715 )
        tr.delete(:exrules)

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

      VALIDATION_PROCS = {
        proc {|d| !d.has_key?(:entities) ||
               ( d[:entities].nil? ||
                 d[:entities].is_a?(Array) &&
                 d[:entities].all? {|e| e.is_a?(String)} ) } =>
        "entities must be a list of strings",

        proc {|d| !d.has_key?(:regex_entities) ||
               ( d[:regex_entities].nil? ||
                 d[:regex_entities].is_a?(Array) &&
                 d[:regex_entities].all? {|e| e.is_a?(String)} ) } =>
        "regex_entities must be a list of strings",

        proc {|d| !d.has_key?(:tags) ||
               ( d[:tags].nil? ||
                 d[:tags].is_a?(Set) &&
                 d[:tags].all? {|et| et.is_a?(String)} ) } =>
        "tags must be a tag_set of strings",

        proc {|d| !d.has_key?(:regex_tags) ||
               ( d[:regex_tags].nil? ||
                 d[:regex_tags].is_a?(Set) &&
                 d[:regex_tags].all? {|et| et.is_a?(String)} ) } =>
        "regex_tags must be a tag_set of strings",

        # conversion to a schedule needs a time zone, any one will do
        proc {|d| !d.has_key?(:time_restrictions) ||
               ( d[:time_restrictions].nil? ||
                 d[:time_restrictions].all? {|tr|
                   !!self.time_restriction_to_icecube_schedule(symbolize(tr), ActiveSupport::TimeZone['UTC'])
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
        tags                = Flapjack.load_json(rule_data['tags'] || '')
        @tags               = tags ? Set.new(tags) : nil
        regex_tags          = Flapjack.load_json(rule_data['regex_tags'] || '')
        @regex_tags         = regex_tags ? Set.new(regex_tags) : nil
        @entities           = Flapjack.load_json(rule_data['entities'] || '')
        @regex_entities     = Flapjack.load_json(rule_data['regex_entities'] || '')
        @time_restrictions  = Flapjack.load_json(rule_data['time_restrictions'] || '')
        @unknown_media      = Flapjack.load_json(rule_data['unknown_media'] || '')
        @warning_media      = Flapjack.load_json(rule_data['warning_media'] || '')
        @critical_media     = Flapjack.load_json(rule_data['critical_media'] || '')
        @unknown_blackhole  = ((rule_data['unknown_blackhole'] || 'false').downcase == 'true')
        @warning_blackhole  = ((rule_data['warning_blackhole'] || 'false').downcase == 'true')
        @critical_blackhole = ((rule_data['critical_blackhole'] || 'false').downcase == 'true')
      end

    end
  end
end

