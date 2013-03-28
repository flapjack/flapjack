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

        return unless redis.exists("notification_rule:#{rule_id}")
        rule = redis.hgetall("notification_rule:#{rule_id}")

        contact_id         = rule['contact_id']
        entity_tags        = Yajl::Parser.parse(rule['entity_tags'] || '')
        entities           = Yajl::Parser.parse(rule['entities'] || '')
        time_restrictions  = Yajl::Parser.parse(rule['time_restrictions'] || '')
        warning_media      = Yajl::Parser.parse(rule['warning_media'] || '')
        critical_media     = Yajl::Parser.parse(rule['critical_media'] || '')
        warning_blackhole  = ((rule['warning_blackhole'] || 'false').downcase == 'true')
        critical_blackhole = ((rule['critical_blackhole'] || 'false').downcase == 'true')

        self.new({:id                 => rule_id,
                  :contact_id         => contact_id,
                  :entity_tags        => entity_tags,
                  :entities           => entities,
                  :time_restrictions  => time_restrictions,
                  :warning_media      => warning_media,
                  :critical_media     => critical_media,
                  :warning_blackhole  => warning_blackhole,
                  :critical_blackhole => critical_blackhole}, :redis => redis)
      end

      # replacing save! etc
      def self.add(rule_data, options)
        raise "Redis connection not set" unless redis = options[:redis]

        self.add_or_update(rule_data, :add => true, :redis => redis)
      end

      # replacing save! etc
      # TODO args should be (rule_id, new_rule_data, options)
      def self.update(rule_data, options)
        raise "Redis connection not set" unless redis = options[:redis]
        raise "A rule id must be supplied" unless rule_id = rule_data[:id]
        raise "No such rule exists with the supplied id: #{rule_id}" unless self.exists_with_id?(rule_id, :redis => redis)

        self.add_or_update(rule_data, :redis => redis)
      end

      # TODO change to self.delete(rule_id)
      def delete!
        @redis.srem("contact_notification_rules:#{self.contact_id}", self.id)
        @redis.del("notification_rule:#{self.id}")
      end

      def to_json(opts = {})
        if opts[:root]
          # { notification_rule: {...} }
        end

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
        return true
        # TODO: return true if current time falls within any of the time restriction periods
        tzstr = @timezone || 'UTC'
        begin
          tz = TZInfo::Timezone.get(tzstr)
        rescue
          @logger.error("Unrecognised timezone string: '#{tzstr}', NotificationRule.match_time? proceeding with UTC")
          tz = TZInfo::Timezone.get('UTC')
        end
        now_secs = tz.utc_to_local
        match = @time_restrictions.find do |tr|
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

      def initialize(rule, opts = {})
        @redis  ||= opts[:redis]
        @logger = opts[:logger]
        raise "a redis connection must be supplied" unless @redis
        raise "contact_id is required" unless
        @contact_id         = rule[:contact_id]
        @id                 = rule[:id]
        @entities           = rule[:entities]
        @entity_tags        = rule[:entity_tags]
        @time_restrictions  = rule[:time_restrictions]
        @warning_media      = rule[:warning_media]
        @critical_media     = rule[:critical_media]
        @warning_blackhole  = rule[:warning_blackhole]
        @critical_blackhole = rule[:critical_blackhole]
      end

      def self.add_or_update(rule_data, options = {})
        redis = options[:redis]

        if options[:add]
          # TODO use a guaranteed UUID
          c = 0
          loop do
            c += 1
            rule_data[:id] = SecureRandom.uuid
            break unless redis.exists("notification_rule:#{rule_data[:id]}")
            raise "unable to find non-clashing UUID for this new notification rule o_O " unless c < 100
          end
        end

        rule_data[:entities]           = Yajl::Encoder.encode(rule_data[:entities])
        rule_data[:entity_tags]        = Yajl::Encoder.encode(rule_data[:entity_tags])
        rule_data[:time_restrictions]  = Yajl::Encoder.encode(rule_data[:time_restrictions])
        rule_data[:warning_media]      = Yajl::Encoder.encode(rule_data[:warning_media])
        rule_data[:critical_media]     = Yajl::Encoder.encode(rule_data[:critical_media])

        redis.sadd("contact_notification_rules:#{rule_data[:contact_id]}", rule_data[:id])
        redis.hmset("notification_rule:#{rule_data[:id]}", *rule_data.flatten)
        self.new(rule_data, :redis => redis)
      end

      # # @warning_media  = [ 'email' ]
      # # @critical_media = [ 'email', 'sms' ]

      # # severity, media match?
      # # nil @warning_media for warning
      # def severity_match?

      # end

    end
  end
end

