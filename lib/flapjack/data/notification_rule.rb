#!/usr/bin/env ruby

require 'yajl/json_gem'

module Flapjack
  module Data
    class NotificationRule

      attr_accessor :tags

      def self.find_by_id(rule_id, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        raise "No id value passed" unless rule_id
        logger   = options[:logger]
        timezone           = options[:timezone]

        return unless rule = redis.hgetall("notification_rule:#{rule_id}")

        entity_tags        = Yajl::Parser.parse(rule['entity_tags'] || '')
        entities           = Yajl::Parser.parse(rule['entities'] || '')
        time_restrictions  = Yajl::Parser.parse(rule['time_restrictions'] || '')
        warning_media      = Yajl::Parser.parse(rule['warning_media'] || '')
        critical_media     = Yajl::Parser.parse(rule['critical_media'] || '')
        warning_blackhole  = rule['warning_blackhole'].downcase == 'true' ? true : false

        self.new(:id                => rule_id,
                 :entity_tags       => entity_tags,
                 :entities          => entities,
                 :time_restrictions => time_restrictions,
                 :warning_media     => warning_media,
                 :critical_media    => critical_media,
                 :timezone          => timezone)
      end

      # tags or entity names match?
      # nil @entity_tags and nil @entities matches
      def match_entity?(event)
        puts "match_entity? event:"
        pp event
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
        puts @time_restrictions.inspect
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
        puts "media_for_severity('#{severity}') - returning [#{media_list.join(', ')}]"
        media_list
      end

    private
      def initialize(opts)
        @entity_tags        = opts[:entity_tags]
        @entities           = opts[:entities]
        @time_restrictions  = opts[:time_restrictions]
        @warning_media      = opts[:warning_media]
        @critical_media     = opts[:critical_media]
        @warning_blackhole  = opts[:warning_blackhole]
        @critical_blackhole = opts[:critical_blackhole]
        @timezone           = opts[:timezone]
        @logger             = opts[:logger]
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

