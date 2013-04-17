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

        rule = self.new({:id => rule_id}, {:redis => redis})
        rule.refresh
        rule
      end

      # replacing save! etc
      def self.add(rule_data, options)
        raise "Redis connection not set" unless redis = options[:redis]

        rule_id = SecureRandom.uuid
        self.add_or_update(rule_data.merge(:id => rule_id), :redis => redis)
        self.find_by_id(rule_id, :redis => redis)
      end

      # add user's timezone string to the hash, deserialise
      # time in the user's timezone also
      def self.time_restriction_to_ice_cube_hash(tr, timezone)
        Time.zone = timezone.identifier
        tr = symbolize(tr)

        tr[:start_date] = tr[:start_time].dup
        tr.delete(:start_time)

        if tr[:start_date].is_a?(String)
          tr[:start_date] = { :time => tr[:start_date] }
        end
        if tr[:start_date].is_a?(Hash)
          tr[:start_date][:time] = Time.zone.parse(tr[:start_date][:time])
          tr[:start_date][:zone] = timezone.identifier
        end

        if tr[:end_time].is_a?(String)
          tr[:end_time] = { :time => tr[:end_time] }
        end
        if tr[:end_time].is_a?(Hash)
          tr[:end_time][:time] = Time.zone.parse(tr[:end_time][:time])
          tr[:end_time][:zone] = timezone.identifier
        end

        # rewrite Weekly to IceCube::WeeklyRule, etc
        tr[:rrules].each {|rrule|
          rrule[:rule_type] = "IceCube::#{rrule[:rule_type]}Rule"
        }

        tr
      end

      def self.time_restriction_from_ice_cube_hash(tr, timezone)
        Time.zone = timezone.identifier

        tr[:start_date] = Time.zone.utc_to_local(tr[:start_date][:time]).strftime "%Y-%m-%d %H:%M:%S"
        tr[:end_time]   = Time.zone.utc_to_local(tr[:end_time][:time]).strftime "%Y-%m-%d %H:%M:%S"

        # rewrite IceCube::WeeklyRule to Weekly, etc
        tr[:rrules].each {|rrule|
          rrule[:rule_type] = /^.*\:\:(.*)Rule$/.match(rrule[:rule_type])[1]
        }

        tr[:start_time] = tr[:start_date].dup
        tr.delete(:start_date)

        tr
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

      def update(rule_data)
        self.class.add_or_update(rule_data, :redis => @redis)
        self.refresh
      end

      def to_json(*args)
        hash = (Hash[ *([:id, :contact_id, :entity_tags, :entities,
                 :time_restrictions, :warning_media, :critical_media,
                 :warning_blackhole, :critical_blackhole].collect {|k|
                   [k, self.send(k)]
                 }).flatten(1) ])
        hash.to_json
      end

      # tags or entity names match?
      # nil @entity_tags and nil @entities matches
      def match_entity?(event)
        return true if (@entity_tags.nil? or @entity_tags.empty?) and
                       (@entities.nil? or @entities.empty?)
        return true if @entities.include?(event.split(':').first)
        # TODO: return true if event's entity tags match entity tag list on the rule
        return false
      end

      def blackhole?(severity)
        return true if 'warning'.eql?(severity.downcase) and @warning_blackhole
        return true if 'critical'.eql?(severity.downcase) and @critical_blackhole
        return false
      end

      def media_for_severity(severity)
        case severity
        when 'warning'
          media_list = @warning_media
        when 'critical'
          media_list = @critical_media
        end
        media_list
      end

    private

      def initialize(rule_data, opts = {})
        @redis  ||= opts[:redis]
        @logger   = opts[:logger]
        raise "a redis connection must be supplied" unless @redis
        @id = rule_data[:id]
      end

      def self.add_or_update(rule_data, options = {})
        redis = options[:redis]

        rule_data[:entities]          = Yajl::Encoder.encode(rule_data[:entities])
        rule_data[:entity_tags]       = Yajl::Encoder.encode(rule_data[:entity_tags])
        rule_data[:time_restrictions] = Yajl::Encoder.encode(rule_data[:time_restrictions])
        rule_data[:warning_media]     = Yajl::Encoder.encode(rule_data[:warning_media])
        rule_data[:critical_media]    = Yajl::Encoder.encode(rule_data[:critical_media])

        redis.sadd("contact_notification_rules:#{rule_data[:contact_id]}", rule_data[:id])
        redis.hmset("notification_rule:#{rule_data[:id]}", *rule_data.flatten)
      end

    end
  end
end

