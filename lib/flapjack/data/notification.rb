#!/usr/bin/env ruby

require 'flapjack/data/contact'
require 'flapjack/data/event'
require 'flapjack/data/message'

module Flapjack
  module Data
    class Notification

      attr_reader :type, :event_id, :event_state

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
        if ([event.state, max_notified_severity] & ['critical', 'unknown', 'test_notifications']).any?
          'critical'
        elsif [event.state, max_notified_severity].include?('warning')
          'warning'
        else
          'ok'
        end
      end

      def self.add(queue, event, opts = {})
        raise "Redis connection not set" unless redis = opts[:redis]

        last_state = opts[:last_state] || {}

        notif = {'event_id'     => event.id,
                 'state'        => event.state,
                 'summary'      => event.summary,
                 'last_state'   => last_state[:state],
                 'last_summary' => last_state[:summary],
                 'details'      => event.details,
                 'time'         => event.time,
                 'duration'     => event.duration || nil,
                 'type'         => opts[:type] || type_for_event(event),
                 'severity'     => opts[:severity] }

        redis.rpush(queue, ::Yajl::Encoder.encode(notif))
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
          parsed = ::JSON.parse( raw )
        rescue => e
          if options[:logger]
            options[:logger].warn("Error deserialising notification json: #{e}, raw json: #{raw.inspect}")
          end
          return nil
        end
        self.new( parsed )
      end

      def messages(contacts, opts = {})
        return [] if contacts.nil? || contacts.empty?

        default_timezone = opts[:default_timezone]
        logger = opts[:logger]

        contents = {'event_id'          => @event_id,
                    'state'             => @event_state,
                    'summary'           => @event_summary,
                    'last_state'        => @last_event_state,
                    'last_summary'      => @last_event_summary,
                    'details'           => @event_details,
                    'time'              => @event_time,
                    'duration'          => @event_duration,
                    'notification_type' => @type }

        @messages ||= contacts.collect {|contact|
          contact_id = contact.id
          rules = contact.notification_rules
          media = contact.media

          logger.debug "considering messages for contact id #{contact_id} #{@event_id} #{@event_state} (media) #{media.inspect}"
          rlen = rules.length
          logger.debug "found #{rlen} rule#{(rlen == 1) ? '' : 's'} for contact"

          media_to_use = if rules.empty?
            media
          else
            # matchers are rules of the contact that have matched the current event
            # for time and entity
            matchers = rules.select do |rule|
              rule.match_entity?(@event_id) &&
                rule_occurring_now?(rule, :contact => contact, :default_timezone => default_timezone)
            end

            logger.debug "#{matchers.length} matchers remain for this contact:"
            matchers.each do |matcher|
              logger.debug "matcher: #{matcher.to_json}"
            end

            # delete any matchers for all entities if there are more specific matchers
            if matchers.any? {|matcher| matcher.is_specific? }

              logger.debug("general removal: found #{matchers.length} entity specific matchers")
              num_matchers = matchers.length

              matchers.reject! {|matcher| !matcher.is_specific? }

              if num_matchers != matchers.length
                logger.debug("notification: removal of general matchers when entity specific matchers are present: number of matchers changed from #{num_matchers} to #{matchers.length} for contact id: #{contact_id}")
              end
            end

            # delete media based on blackholes
            next if matchers.any? {|matcher| matcher.blackhole?(@event_state) }

            logger.debug "notification: num matchers after removing blackhole matchers: #{matchers.size}"

            rule_media = matchers.collect{|matcher|
              matcher.media_for_severity(@severity)
            }.flatten.uniq

            logger.debug "notification: collected media_for_severity(#{@severity}): #{rule_media}"
            rule_media = rule_media.reject {|medium|
              contact.drop_notifications?(:media => medium,
                                          :check => @event_id,
                                          :state => @event_state)
            }

            logger.debug "notification: media after contact_drop?: #{rule_media}"

            media.select {|medium, address| rule_media.include?(medium) }
          end

          logger.debug "notification: media_to_use: #{media_to_use}"

          # puts logger.messages.join("\n")

          media_to_use.each_pair.inject([]) { |ret, (k, v)|
            m = Flapjack::Data::Message.for_contact(contact,
              :notification_contents => contents,
              :medium => k, :address => v)
            ret << m
            ret
          }
        }.compact.flatten
      end

    private

      # created from parsed JSON, so opts keys are in strings
      def initialize(opts = {})
        @event_id       = opts['event_id']
        @event_state    = opts['state']
        @event_summary  = opts['summary']
        @event_details  = opts['details']
        @event_time     = opts['time']
        @event_duration = opts['duration']

        @last_event_state   = opts['last_state']
        @last_event_summary = opts['last_summary']

        @type           = opts['type']
        @severity       = opts['severity']
      end

      # # time restrictions match?
      # nil rule.time_restrictions matches
      # times (start, end) within time restrictions will have any UTC offset removed and will be
      # considered to be in the timezone of the contact
      def rule_occurring_now?(rule, options = {})
        contact = options[:contact]
        def_tz = options[:default_timezone]

        return true if rule.time_restrictions.nil? or rule.time_restrictions.empty?

        timezone = contact.timezone(:default => def_tz)
        usertime = timezone.now

        rule.time_restrictions.any? do |tr|
          # add contact's timezone to the time restriction schedule
          schedule = Flapjack::Data::NotificationRule.
                       time_restriction_to_icecube_schedule(tr, timezone)
          schedule && schedule.occurring_at?(usertime)
        end
      end

    end
  end
end

