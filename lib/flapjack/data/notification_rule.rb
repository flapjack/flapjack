#!/usr/bin/env ruby

require 'yajl/json_gem'

module Flapjack
  module Data
    class NotificationRule

      attr_accessor :id, :contact_id, :entities, :entity_tags, :time_restrictions,
        :warning_media, :critical_media, :warning_blackhole, :critical_blackhole

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

      def delete!
        @redis.srem("contact_notification_rules:#{self.contact_id}", self.id)
        @redis.del("notification_rule:#{self.id}")
      end

      def as_json(opts = {})
        if opts[:root]
          # { notification_rule: {...} }
        end

        buf = { "rule_id"            => self.id,
                "contact_id"         => self.contact_id,
                "entity_tags"        => self.entity_tags,
                "entities"           => self.entities,
                "time_restrictions"  => self.time_restrictions,
                "warning_media"      => self.warning_media,
                "critical_media"     => self.critical_media,
                "warning_blackhole"  => self.warning_blackhole,
                "critical_blackhole" => self.critical_blackhole }

        buf.to_json
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

      def save!
        rule = {}
        rule['contact_id']         = @contact_id
        rule['entities']           = Yajl::Encoder.encode(@entities)
        rule['entity_tags']        = Yajl::Encoder.encode(@entity_tags)
        rule['time_restrictions']  = Yajl::Encoder.encode(@time_restrictions)
        rule['warning_media']      = Yajl::Encoder.encode(@warning_media)
        rule['critical_media']     = Yajl::Encoder.encode(@critical_media)
        rule['warning_blackhole']  = @warning_blackhole
        rule['critical_blackhole'] = @critical_blackhole

        @redis.sadd("contact_notification_rules:#{@contact_id}", self.id)
        @redis.hmset("notification_rule:#{self.id}", *rule.flatten)
      end

    private
      def initialize(rule, opts = {})
        @redis  ||= opts[:redis]
        @logger = opts[:logger]
        raise "a redis connection must be supplied" unless @redis
        raise "contact_id is required" unless
          @contact_id       = rule[:contact_id]
        @entities           = rule[:entities]
        @entity_tags        = rule[:entity_tags]
        @time_restrictions  = rule[:time_restrictions]
        @warning_media      = rule[:warning_media]
        @critical_media     = rule[:critical_media]
        @warning_blackhole  = rule[:warning_blackhole]
        @critical_blackhole = rule[:critical_blackhole]
        if not rule[:id]
          c = 0
          loop do
            c += 1
            rule[:id] = SecureRandom.uuid
            break unless @redis.exists("notification_rule:#{rule[:id]}")
            raise "unable to find non-clashing UUID for this new notification rule o_O " unless c < 100
          end
          @id = rule[:id]
          self.save!
        else
          @id = rule[:id]
        end
      end

      # @warning_media  = [ 'email' ]
      # @critical_media = [ 'email', 'sms' ]

      # severity, media match?
      # nil @warning_media for warning
      def severity_match?

      end

    end
  end
end

