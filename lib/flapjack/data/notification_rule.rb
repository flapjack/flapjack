#!/usr/bin/env ruby

require 'yajl/json_gem'

module Flapjack
  module Data
    class NotificationRule

      attr_accessor :tags

      def self.find_by_id(rule_id, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        raise "No id value passed" unless rule_id
        logger = options[:logger]

        return unless rule = redis.hget("notification_rule:#{rule_id}")

        entity_tags        = Yajl::Parser.parse(rule['entity_tags'] || '')
        entities           = Yajl::Parser.parse(rule['entities'] || '')
        time_restrictions  = Yajl::Parser.parse(rule['time_restrictions'] || '')
        warning_media      = Yajl::Parser.parse(rule['warning_media'] || '')
        critical_media     = Yajl::Parser.parse(rule['critical_media'] || '')
        warning_blackhole  = rule['warning_blackhole'].downcase == 'true' ? true : false
        critical_blackhole = rule['critical_blackhole'].downcase == 'true' ? true : false

        self.new(:id                => rule_id,
                 :entity_tags       => entity_tags,
                 :entities          => entities,
                 :time_restrictions => time_restrictions,
                 :warning_media     => warning_media,
                 :critical_media    => critical_media)
      and

      # tags or entity names match?
      # nil @entity_tags and nil @entities matches
      def match_entity?(event)
        return true if (@entity_tags.nil? or @entity_tags.empty?) and
                       (@entities.nil? or @entities.empty?)
        return false
      end

      # time restrictions match?
      # nil @time_restrictions matches
      def match_time?(event)
        return true if @time_restrictions.nil? or @time_restrictions.empty?
        return false
      end

      def blackhole?(severity)
        return true if 'warning'.eql?(severity.downcase) and @warning_blackhole
        return true if 'critical'.eql?(severity.downcase) and @critical_blackhole
        return false
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

