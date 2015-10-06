#!/usr/bin/env ruby

require 'flapjack/data/contact'
require 'flapjack/data/event'
require 'flapjack/data/message'

module Flapjack
  module Data
    class Notification

      attr_reader :type, :event_id, :state

      def self.type_for_event(event)
        case event.type
        when 'service'
          case event.state
          when 'ok'
            'recovery'
          when 'warning', 'critical', 'unknown'
            'problem'
          end
        when 'action'
          case event.state
          when 'acknowledgement'
            'acknowledgement'
          when 'test_notifications'
            'test'
          end
        else
          'unknown'
        end
      end

      def self.severity_for_event(event, max_notified_severity)
        if ([event.state, max_notified_severity] & ['critical', 'test_notifications']).any?
          'critical'
        elsif [event.state, max_notified_severity].include?('warning')
          'warning'
        elsif [event.state, max_notified_severity].include?('unknown')
          'unknown'
        else
          'ok'
        end
      end

      def self.add(queue, event, opts = {})
        raise "Redis connection not set" unless redis = opts[:redis]

        last_state = opts[:last_state] || {}

        tag_data = event.tags.is_a?(Set) ? event.tags.to_a : nil
        notif = {'event_id'       => event.id,
                 'event_hash'     => event.id_hash,
                 'state'          => event.state,
                 'summary'        => event.summary,
                 'details'        => event.details,
                 'time'           => event.time,
                 'duration'       => event.duration,
                 'count'          => event.counter,
                 'last_state'     => last_state[:state],
                 'last_summary'   => last_state[:summary],
                 'state_duration' => opts[:state_duration],
                 'type'           => opts[:type] || type_for_event(event),
                 'severity'       => opts[:severity],
                 'tags'           => tag_data }

        redis.rpush(queue, Flapjack.dump_json(notif))
      end

      def self.next(queue, opts = {})
        raise "Redis connection not set" unless redis = opts[:redis]

        defaults = { :block => true }
        options  = defaults.merge(opts)

        if options[:block]
          raw = redis.blpop(queue, 0)[1]
        else
          raw = redis.lpop(queue)
          return unless raw
        end
        begin
          parsed = ::Flapjack.load_json( raw )
        rescue Oj::Error => e
          if options[:logger]
            options[:logger].warn("Error deserialising notification json: #{e}, raw json: #{raw.inspect}")
          end
          return
        end
        return if 'shutdown'.eql?(parsed['type'])
        self.new( parsed )
      end

      def ok?
        @state && ['ok', 'up'].include?(@state)
      end

      def acknowledgement?
        @state && ['acknowledgement'].include?(@state)
      end

      def test?
        @state && ['test_notifications'].include?(@state)
      end

      def contents
        @contents ||= {'event_id'          => @event_id,
                       'event_hash'        => @event_hash,
                       'state'             => @state,
                       'summary'           => @summary,
                       'duration'          => @duration,
                       'last_state'        => @last_state,
                       'last_summary'      => @last_summary,
                       'state_duration'    => @state_duration,
                       'details'           => @details,
                       'time'              => @time,
                       'notification_type' => @type,
                       'event_count'       => @count,
                       'tags'              => @tags
                      }
      end

      def messages(contacts, opts = {})
        return [] if contacts.nil? || contacts.empty?

        default_timezone = opts[:default_timezone]
        logger = opts[:logger]

        @messages ||= contacts.collect do |contact|
          contact_id = contact.id
          rules = contact.notification_rules
          media = contact.media

          logger.debug "Notification#messages: creating messages for contact: #{contact_id} " +
            "event_id: \"#{@event_id}\" state: #{@state} event_tags: #{Flapjack.dump_json(@tags)} media: #{media.inspect}"
          rlen = rules.length
          logger.debug "found #{rlen} rule#{(rlen == 1) ? '' : 's'} for contact #{contact_id}"

          media_to_use = if rules.empty?
            media
          else
            # matchers are rules of the contact that have matched the current event
            # for time, entity and tags
            matchers = rules.select do |rule|
              begin
                logger.debug("considering rule with entities: #{rule.entities}, entities regex: #{rule.regex_entities},
                             tags: #{Flapjack.dump_json(rule.tags)} and regex tags: #{Flapjack.dump_json(rule.regex_tags)}")
                rule_has_tags           = rule.tags           ? (rule.tags.length > 0)           : false
                rule_has_regex_tags     = rule.regex_tags     ? (rule.regex_tags.length > 0)     : false
                rule_has_entities       = rule.entities       ? (rule.entities.length > 0)       : false
                rule_has_regex_entities = rule.regex_entities ? (rule.regex_entities.length > 0) : false

                matches_tags           = rule_has_tags           ? rule.match_tags?(@tags)               : true
                matches_regex_tags     = rule_has_regex_tags     ? rule.match_regex_tags?(@tags)         : true
                matches_entity         = rule_has_entities       ? rule.match_entity?(@event_id)         : true
                matches_regex_entities = rule_has_regex_entities ? rule.match_regex_entities?(@event_id) : true

                ((matches_entity && matches_regex_entities && matches_tags && matches_regex_tags) || ! rule.is_specific?) &&
                  rule_occurring_now?(rule, :contact => contact, :default_timezone => default_timezone,
                    :logger => logger)
              rescue RegexpError => e
                logger.error "rule with entities regex: #{rule.regex_entities} and regex tags: #{Flapjack.dump_json(rule.regex_tags)} has invalid regex: #{e.message}"
                false
              end
            end

            logger.debug "#{matchers.length} matchers remain for this contact after time, entity and tags are matched:"
            matchers.each do |matcher|
              logger.debug "  - #{matcher.to_jsonapi}"
            end

            # delete any general matchers if there are more specific matchers left
            if matchers.any? {|matcher| matcher.is_specific? }

              num_matchers = matchers.length

              matchers.reject! {|matcher| !matcher.is_specific? }

              if num_matchers != matchers.length
                logger.debug("removal of general matchers when entity specific matchers are present: number of matchers changed from #{num_matchers} to #{matchers.length} for contact id: #{contact_id}")
                matchers.each do |matcher|
                  logger.debug "  - #{matcher.to_jsonapi}"
                end
              end
            end

            # delete media based on blackholes
            blackhole_matchers = matchers.map {|matcher| matcher.blackhole?(@severity) ? matcher : nil }.compact
            if blackhole_matchers.length > 0
              logger.debug "dropping this media as #{blackhole_matchers.length} blackhole matchers are present:"
              blackhole_matchers.each {|bm|
                logger.debug "  - #{bm.to_jsonapi}"
              }
              next
            else
              logger.debug "no blackhole matchers matched"
            end

            rule_media = matchers.collect{|matcher|
              matcher.media_for_severity(@severity)
            }.flatten.uniq

            logger.debug "collected media_for_severity(#{@severity}): #{rule_media}"
            rule_media = rule_media.reject {|medium|
              contact.drop_notifications?(:media => medium,
                                          :check => @event_id,
                                          :state => @state)
            }

            logger.debug "media after contact_drop?: #{rule_media}"

            media.select {|medium, address| rule_media.include?(medium) }
          end

          logger.debug "media_to_use: #{media_to_use}"

          # here begins rollup madness
          media_to_use.each_pair.inject([]) do |ret, (media, address)|
            rollup_type = nil

            contact.add_alerting_check_for_media(media, @event_id) unless ok? || acknowledgement? || test?

            # expunge checks in (un)scheduled maintenance from the alerting set
            recovered = contact.clean_alerting_checks_for_media(media)
            logger.debug("cleaned alerting checks for #{media}: recovered? #{recovered}")

            # pagerduty is an example of a medium which should never be rolled up
            unless ['pagerduty'].include?(media)
              alerting_checks  = contact.count_alerting_checks_for_media(media)
              rollup_threshold = contact.rollup_threshold_for_media(media)

              case
              when rollup_threshold.nil?
                # back away slowly
              when alerting_checks >= rollup_threshold
                if contact.drop_rollup_notifications_for_media?(media)
                  logger.debug "rollup decisions: #{@event_id} #{@state} #{media} #{address} skip because in rollup mode"
                  next ret
                end
                contact.update_sent_rollup_alert_keys_for_media(media, :delete => false)
                rollup_type = 'problem'
              when recovered
                # alerting checks was just cleaned such that it is now below the rollup threshold
                contact.update_sent_rollup_alert_keys_for_media(media, :delete => true)
                rollup_type = 'recovery'
              end
              logger.debug "rollup decisions: #{@event_id} #{@state} #{media} #{address} rollup_type: #{rollup_type}"
            end

            m = Flapjack::Data::Message.for_contact(contact,
                  :medium => media, :address => address, :rollup => rollup_type)
            ret << m
            ret
          end
        end.compact.flatten # @messages ||= contacts.collect do ...
      end

    private

      # created from parsed JSON, so opts keys are in strings
      def initialize(opts = {})
        @event_id       = opts['event_id']
        @state          = opts['state']
        @summary        = opts['summary']
        @details        = opts['details']
        @time           = opts['time']
        @count          = opts['count']
        @duration       = opts['duration']
        @last_state     = opts['last_state']
        @last_summary   = opts['last_summary']
        @state_duration = opts['state_duration']
        @type           = opts['type']
        @severity       = opts['severity']
        @tags           = opts['tags'].is_a?(Array) ? Set.new(opts['tags']) : nil
      end

      # # time restrictions match?
      # nil rule.time_restrictions matches
      # times (start, end) within time restrictions will have any UTC offset removed and will be
      # considered to be in the timezone of the contact
      def rule_occurring_now?(rule, options = {})
        contact = options[:contact]
        def_tz = options[:default_timezone]

        return true if rule.time_restrictions.nil? or rule.time_restrictions.empty?

        time_zone = contact.time_zone || def_tz
        usertime = time_zone.now

        rule.time_restrictions.any? do |tr|
          # add contact's time_zone to the time restriction schedule
          schedule = Flapjack::Data::NotificationRule.
                       time_restriction_to_icecube_schedule(tr, time_zone, :logger => options[:logger])
          schedule && schedule.occurring_at?(usertime)
        end
      end

    end
  end
end

