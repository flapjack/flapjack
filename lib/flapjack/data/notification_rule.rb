#!/usr/bin/env ruby

require 'yajl/json_gem'

module Flapjack
  module Data
    class NotificationRule

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

        @time_restrictions = @time_restrictions.map do |tr|
          tr['start_date'] = Time.parse(tr['start_date'])
          tr['end_time']   = Time.parse(tr['end_time'])
          tr
        end
      end

      def update(rule_data)
        self.class.add_or_update(rule_data, :redis => @redis)
        self.refresh
      end

      def to_json(*args)
        (Hash[ *([:id, :contact_id, :entity_tags, :entities,
          :time_restrictions, :warning_media, :critical_media,
          :warning_blackhole, :critical_blackhole].collect {|k|
            [k, self.send(k)]
          }).flatten(1) ]).to_json
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

      # time restrictions match?
      # nil @time_restrictions matches
      def match_time?
        return true if @time_restrictions.nil? or @time_restrictions.empty?

        tzstr = @timezone || 'UTC'
        begin
          tz = TZInfo::Timezone.get(tzstr)
        rescue
          @logger.error("Unrecognised timezone string: '#{tzstr}', NotificationRule.match_time? proceeding with UTC")
          tz = TZInfo::Timezone.get('UTC')
        end
        usertime = tz.utc_to_local(Time.now.utc)

        match = @time_restrictions.any? do |tr|
          schedule = IceCube::Schedule.from_hash(tr)
          schedule.occurring_at?(usertime)
        end
        return true if match
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
        @logger = opts[:logger]
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

