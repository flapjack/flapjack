#!/usr/bin/env ruby

# 'Notification' refers to the template object created when an event occurs,
# from which individual 'Message' objects are created, one for each
# contact+media recipient.

require 'oj'

require 'flapjack/data/contact'
require 'flapjack/data/event'
require 'flapjack/data/message'

module Flapjack
  module Data
    class Notification

      attr_reader :type, :event_id, :event_state, :event_count

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

      def self.push(queue, event, opts = {})
        last_state = opts[:last_state] || {}

        tag_data = event.tags.is_a?(Set) ? event.tags.to_a : nil
        notif = {'event_id'     => event.id,
                 'state'        => event.state,
                 'summary'      => event.summary,
                 'last_state'   => last_state[:state],
                 'last_summary' => last_state[:summary],
                 'details'      => event.details,
                 'time'         => event.time,
                 'duration'     => event.duration || nil,
                 'type'         => opts[:type] || type_for_event(event),
                 'severity'     => opts[:severity],
                 'count'        => event.counter,
                 'tags'         => tag_data }

        begin
          notif_json = Oj.dump(notif)
        rescue Oj::Error => e
          if opts[:logger]
            opts[:logger].warn("Error serialising notification json: #{e}, notification: #{notif.inspect}")
          end
          notif_json = nil
        end

        if notif_json
          Flapjack.redis.multi do
            Flapjack.redis.lpush(queue, notif_json)
            Flapjack.redis.lpush("#{queue}_actions", "+")
          end
        end

      end

      def self.foreach_on_queue(queue)
        while notif_json = Flapjack.redis.rpop(queue)
          begin
            notification = ::Oj.load( notif_json )
          rescue Oj::Error => e
            if opts[:logger]
              opts[:logger].warn("Error deserialising notification json: #{e}, raw json: #{notif_json.inspect}")
            end
            notification = nil
          end

          yield self.new(notification) if block_given? && notification
        end
      end

      def self.wait_for_queue(queue)
        Flapjack.redis.brpop("#{queue}_actions")
      end

      def contents
        @contents ||= {'event_id'          => @event_id,
                       'state'             => @event_state,
                       'summary'           => @event_summary,
                       'last_state'        => @last_event_state,
                       'last_summary'      => @last_event_summary,
                       'details'           => @event_details,
                       'time'              => @event_time,
                       'duration'          => @event_duration,
                       'notification_type' => @type,
                       'event_count'       => @event_count,
                       'tags'              => @tags
                      }
      end

      def messages(contacts, opts = {})
        return [] if contacts.nil? || contacts.empty?

        default_timezone = opts[:default_timezone]
        logger = opts[:logger]

        @messages ||= contacts.collect {|contact|
          contact_id = contact.id
          rules = contact.notification_rules
          media = contact.media

          logger.debug "Notification#messages: creating messages for contact: #{contact_id} " +
            "event_id: \"#{@event_id}\" state: #{@event_state} event_tags: #{@tags.to_json} media: #{media.inspect}"
          rlen = rules.length
          logger.debug "found #{rlen} rule#{(rlen == 1) ? '' : 's'} for contact #{contact_id}"

          media_to_use = if rules.empty?
            media
          else
            # matchers are rules of the contact that have matched the current event
            # for time, entity and tags
            matchers = rules.select do |rule|
              logger.debug("considering rule with entities: #{rule.entities} and tags: #{rule.tags.to_json}")
              (rule.match_entity?(@event_id) || rule.match_tags?(@tags) || ! rule.is_specific?) &&
                rule_occurring_now?(rule, :contact => contact, :default_timezone => default_timezone)
            end

            logger.debug "#{matchers.length} matchers remain for this contact after time, entity and tags are matched:"
            matchers.each do |matcher|
              logger.debug "  - #{matcher.to_json}"
            end

            # delete any general matchers if there are more specific matchers left
            if matchers.any? {|matcher| matcher.is_specific? }

              num_matchers = matchers.length

              matchers.reject! {|matcher| !matcher.is_specific? }

              if num_matchers != matchers.length
                logger.debug("removal of general matchers when entity specific matchers are present: number of matchers changed from #{num_matchers} to #{matchers.length} for contact id: #{contact_id}")
                matchers.each do |matcher|
                  logger.debug "  - #{matcher.to_json}"
                end
              end
            end

            # delete media based on blackholes
            blackhole_matchers = matchers.map {|matcher| matcher.blackhole?(@severity) ? matcher : nil }.compact
            if blackhole_matchers.length > 0
              logger.debug "dropping this media as #{blackhole_matchers.length} blackhole matchers are present:"
              blackhole_matchers.each {|bm|
                logger.debug "  - #{bm.to_json}"
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
                                          :state => @event_state)
            }

            logger.debug "media after contact_drop?: #{rule_media}"

            media.select {|medium, address| rule_media.include?(medium) }
          end

          logger.debug "media_to_use: #{media_to_use}"

          media_to_use.each_pair.inject([]) { |ret, (k, v)|
            m = Flapjack::Data::Message.for_contact(contact,
                  :medium => k, :address => v)
            ret << m
            ret
          }
        }.compact.flatten
      end

    private

      # created from parsed JSON, so opts keys are in strings
      def initialize(opts = {})
        @event_id           = opts['event_id']
        @event_state        = opts['state']
        @event_summary      = opts['summary']
        @event_details      = opts['details']
        @event_time         = opts['time']
        @event_duration     = opts['duration']
        @event_count        = opts['count']
        @last_event_state   = opts['last_state']
        @last_event_summary = opts['last_summary']
        @type               = opts['type']
        @severity           = opts['severity']
        tags                = opts['tags']
        @tags               = tags.is_a?(Array) ? Flapjack::Data::TagSet.new(tags) : nil
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

