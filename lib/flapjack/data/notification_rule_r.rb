#!/usr/bin/env ruby

require 'oj'
require 'active_support/time'
require 'flapjack/utility'

require 'flapjack/data/redis_record'
require 'flapjack/data/tag_set'

module Flapjack
  module Data
    class NotificationRuleR

      extend Flapjack::Utility

      include Flapjack::Data::RedisRecord

      # TODO port to Redis data-types as redis_record supports them
      define_attributes :entities => :set,
                        :tags => :set,
                        :time_restrictions => :json_string,
                        :warning_media => :set,
                        :critical_media => :set,
                        :warning_blackhole => :boolean,
                        :critical_blackhole => :boolean

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

    # # TODO via AM::Serialization
    #   def to_json(*args)
    #     self.class.hashify(:id, :contact_id, :tags, :entities,
    #         :time_restrictions, :warning_media, :critical_media,
    #         :warning_blackhole, :critical_blackhole) {|k|
    #       [k, self.send(k)]
    #     }.to_json
    #   end

      # entity names match?
      def match_entity?(event_id)
        entities.present? && entities.include?(event_id.split(':').first)
      end

      # tags match?
      def match_tags?(event_tags)
        tags.present? && tags.subset?(event_tags)
      end

      def blackhole?(severity)
        case severity
        when 'warning'
          self.warning_blackhole
        when 'critical'
          self.critical_blackhole
        end
      end

      def media_for_severity(severity)
        case severity
        when 'warning'
          self.warning_media
        when 'critical'
          self.critical_media
        end
      end

      def is_specific?
        entities.present? || tags.present?
      end

    # private

    #   def self.add_or_update(rule_data, options = {})
    #     logger = options[:logger]

    #     # make some assumptions about the incoming data
    #     rule_data[:warning_blackhole]  = rule_data[:warning_blackhole] || false
    #     rule_data[:critical_blackhole] = rule_data[:critical_blackhole] || false
    #     if rule_data[:tags].is_a?(Array)
    #       rule_data[:tags] = Flapjack::Data::TagSet.new(rule_data[:tags])
    #     end

    #     errors = self.validate_data(rule_data, :logger => options[:logger])

    #     return errors unless errors.nil? || errors.empty?

    #     # whitelisting fields, rather than passing through submitted data directly
    #     tag_data = rule_data[:tags].is_a?(Set) ? rule_data[:tags].to_a : nil
    #     json_rule_data = {
    #       :id                 => rule_data[:id].to_s,
    #       :contact_id         => rule_data[:contact_id].to_s,
    #       :entities           => Oj.dump(rule_data[:entities]),
    #       :tags               => Oj.dump(tag_data),
    #       :time_restrictions  => Oj.dump(rule_data[:time_restrictions]),
    #       :warning_media      => Oj.dump(rule_data[:warning_media]),
    #       :critical_media     => Oj.dump(rule_data[:critical_media]),
    #       :warning_blackhole  => rule_data[:warning_blackhole],
    #       :critical_blackhole => rule_data[:critical_blackhole],
    #     }
    #     logger.debug("NotificationRule#add_or_update json_rule_data: #{json_rule_data.inspect}") if logger

    #     Flapjack.redis.sadd("contact_notification_rules:#{json_rule_data[:contact_id]}",
    #                         json_rule_data[:id])
    #     Flapjack.redis.hmset("notification_rule:#{json_rule_data[:id]}",
    #                          *json_rule_data.flatten)
    #     nil
    #   end

    #   def self.prepare_time_restriction(time_restriction, timezone = nil)
    #     # this will hand back a 'deep' copy
    #     tr = symbolize(time_restriction)

    #     return unless tr.has_key?(:start_time) && tr.has_key?(:end_time)

    #     parsed_time = proc {|t|
    #       if t.is_a?(Time)
    #         t
    #       else
    #         begin; (timezone || Time).parse(t); rescue ArgumentError; nil; end
    #       end
    #     }

    #     start_time = case tr[:start_time]
    #     when String, Time
    #       parsed_time.call(tr.delete(:start_time).dup)
    #     when Hash
    #       time_hash = tr.delete(:start_time).dup
    #       parsed_time.call(time_hash[:time])
    #     end

    #     end_time = case tr[:end_time]
    #     when String, Time
    #       parsed_time.call(tr.delete(:end_time).dup)
    #     when Hash
    #       time_hash = tr.delete(:end_time).dup
    #       parsed_time.call(time_hash[:time])
    #     end

    #     return unless start_time && end_time

    #     tr[:start_date] = timezone ?
    #                         {:time => start_time, :zone => timezone.name} :
    #                         start_time

    #     tr[:end_date]   = timezone ?
    #                         {:time => end_time, :zone => timezone.name} :
    #                         end_time

    #     tr[:duration]   = end_time - start_time

    #     # check that rrule types are valid IceCube rule types
    #     return unless tr[:rrules].is_a?(Array) &&
    #       tr[:rrules].all? {|rr| rr.is_a?(Hash)} &&
    #       (tr[:rrules].map {|rr| rr[:rule_type]} -
    #        ['Daily', 'Hourly', 'Minutely', 'Monthly', 'Secondly',
    #         'Weekly', 'Yearly']).empty?

    #     # rewrite Weekly to IceCube::WeeklyRule, etc
    #     tr[:rrules].each {|rrule|
    #       rrule[:rule_type] = "IceCube::#{rrule[:rule_type]}Rule"
    #     }

    #     # TODO does this need to check classes for the following values?
    #     # "validations": {
    #     #   "day": [1,2,3,4,5]
    #     # },
    #     # "interval": 1,
    #     # "week_start": 0

    #     tr
    #   end

    #   def self.validate_data(d, options = {})
    #     # hash with validation => error_message
    #     validations = {proc { d.has_key?(:id) } =>
    #                    "id not set",

    #                    proc { !d.has_key?(:entities) ||
    #                           ( d[:entities].nil? ||
    #                             d[:entities].is_a?(Array) &&
    #                             d[:entities].all? {|e| e.is_a?(String)} ) } =>
    #                    "entities must be a list of strings",

    #                    proc { !d.has_key?(:tags) ||
    #                           ( d[:tags].nil? ||
    #                             d[:tags].is_a?(Flapjack::Data::TagSet) &&
    #                             d[:tags].all? {|et| et.is_a?(String)} ) } =>
    #                    "tags must be a tag_set of strings",

    #                    proc { !d.has_key?(:time_restrictions) ||
    #                           ( d[:time_restrictions].nil? ||
    #                             d[:time_restrictions].all? {|tr|
    #                               !!prepare_time_restriction(symbolize(tr))
    #                             } )
    #                         } =>
    #                    "time restrictions are invalid",

    #                    # TODO should the media types be checked against a whitelist?
    #                    proc { !d.has_key?(:warning_media) ||
    #                           ( d[:warning_media].nil? ||
    #                             d[:warning_media].is_a?(Array) &&
    #                             d[:warning_media].all? {|et| et.is_a?(String)} ) } =>
    #                    "warning_media must be a list of strings",

    #                    proc { !d.has_key?(:critical_media) ||
    #                           ( d[:critical_media].nil? ||
    #                             d[:critical_media].is_a?(Array) &&
    #                             d[:critical_media].all? {|et| et.is_a?(String)} ) } =>
    #                    "critical_media must be a list of strings",

    #                    proc { !d.has_key?(:warning_blackhole) ||
    #                           [TrueClass, FalseClass].include?(d[:warning_blackhole].class) } =>
    #                    "warning_blackhole must be true or false",

    #                    proc { !d.has_key?(:critical_blackhole) ||
    #                           [TrueClass, FalseClass].include?(d[:critical_blackhole].class) } =>
    #                    "critical_blackhole must be true or false",
    #                   }

    #     errors = validations.keys.inject([]) {|ret,vk|
    #       ret << "Rule #{validations[vk]}" unless vk.call
    #       ret
    #     }

    #     return if errors.empty?

    #     if logger = options[:logger]
    #       error_str = errors.join(", ")
    #       logger.info "validation error: #{error_str}"
    #       logger.debug "rule failing validations: #{d.inspect}"
    #     end
    #     errors
    #   end

    #   def refresh
    #     rule_data = Flapjack.redis.hgetall("notification_rule:#{@id}")

    #     @contact_id         = rule_data['contact_id']
    #     tags                = Oj.load(rule_data['tags'] || '')
    #     @tags               = tags ? Flapjack::Data::TagSet.new(tags) : nil
    #     @entities           = Oj.load(rule_data['entities'] || '')
    #     @time_restrictions  = Oj.load(rule_data['time_restrictions'] || '')
    #     @warning_media      = Oj.load(rule_data['warning_media'] || '')
    #     @critical_media     = Oj.load(rule_data['critical_media'] || '')
    #     @warning_blackhole  = ((rule_data['warning_blackhole'] || 'false').downcase == 'true')
    #     @critical_blackhole = ((rule_data['critical_blackhole'] || 'false').downcase == 'true')
    #   end

    end
  end
end

