#!/usr/bin/env ruby

require 'flapjack/data/contact'
require 'flapjack/data/event'
require 'flapjack/data/message'

module Flapjack
  module Data
    class Notification

      attr_reader :event, :type, :max_notified_severity, :contacts,
        :default_timezone, :last_state

      def self.for_event(event, opts = {})
        self.new(:event => event,
                 :type => opts[:type],
                 :max_notified_severity => opts[:max_notified_severity],
                 :contacts => opts[:contacts],
                 :default_timezone => opts[:default_timezone],
                 :last_state => opts[:last_state],
                 :logger => opts[:logger])
      end

      def messages
        return [] if contacts.nil? || contacts.empty?

        event_id = event.id
        event_state = event.state

        severity = if ([event_state, max_notified_severity] & ['critical', 'unknown', 'test_notifications']).any?
          'critical'
        elsif [event_state, max_notified_severity].include?('warning')
          'warning'
        else
          'ok'
        end

        contents = {'event_id'              => event_id,
                    'state'                 => event_state,
                    'summary'               => event.summary,
                    'last_state'            => @last_state ? @last_state[:state] : nil,
                    'last_summary'          => @last_state ? @last_state[:summary] : nil,
                    'details'               => event.details,
                    'time'                  => event.time,
                    'duration'              => event.duration || nil,
                    'notification_type'     => type,
                    'max_notified_severity' => max_notified_severity }

        @messages ||= contacts.collect {|contact|
          contact_id = contact.id
          rules = contact.notification_rules
          media = contact.media

          @logger.debug "considering messages for contact id #{contact_id} #{event_id} #{event_state} (media) #{media.inspect}"
          rlen = rules.length
          @logger.debug "found #{rlen} rule#{(rlen == 1) ? '' : 's'} for contact"

          media_to_use = if rules.empty?
            media
          else
            # matchers are rules of the contact that have matched the current event
            # for time and entity
            matchers = rules.select do |rule|
              rule.match_entity?(event_id) &&
                rule_occurring_now?(rule, :contact => contact, :default_timezone => default_timezone)
            end

            @logger.debug "#{matchers.length} matchers remain for this contact:"
            matchers.each do |matcher|
              @logger.debug "matcher: #{matcher.to_json}"
            end

            # delete any matchers for all entities if there are more specific matchers
            if matchers.any? {|matcher| matcher.is_specific? }

              @logger.debug("general removal: found #{matchers.length} entity specific matchers")
              num_matchers = matchers.length

              matchers.reject! {|matcher| !matcher.is_specific? }

              if num_matchers != matchers.length
                @logger.debug("notification: removal of general matchers when entity specific matchers are present: number of matchers changed from #{num_matchers} to #{matchers.length} for contact id: #{contact_id}")
              end
            end

            # delete media based on blackholes
            next if matchers.any? {|matcher| matcher.blackhole?(event_state) }

            @logger.debug "notification: num matchers after removing blackhole matchers: #{matchers.size}"

            rule_media = matchers.collect{|matcher|
              matcher.media_for_severity(severity)
            }.flatten.uniq

            @logger.debug "notification: collected media_for_severity(#{severity}): #{rule_media}"
            rule_media = rule_media.flatten.uniq.reject {|medium|
              contact.drop_notifications?(:media => medium,
                                          :check => event_id,
                                          :state => event_state)
            }

            @logger.debug "notification: media after contact_drop?: #{rule_media}"

            media.select {|medium, address| rule_media.include?(medium) }
          end

          @logger.debug "notification: media_to_use: #{media_to_use}"

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

      def initialize(opts = {})
        raise "Event not passed" unless event = opts[:event]
        @event = event
        @type  = opts[:type]
        @max_notified_severity = opts[:max_notified_severity]
        @contacts = opts[:contacts]
        @default_timezone = opts[:default_timezone]
        @last_state = opts[:last_state]
        @logger = opts[:logger]
      end

      # # time restrictions match?
      # nil rule.time_restrictions matches
      # times (start, end) within time restrictions will have any UTC offset removed and will be
      # considered to be in the timezone of the contact
      def rule_occurring_now?(rule, options = {})
        contact = options[:contact]
        default_timezone = options[:default_timezone]

        return true if rule.time_restrictions.nil? or rule.time_restrictions.empty?

        timezone = contact.timezone(:default => default_timezone)
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

