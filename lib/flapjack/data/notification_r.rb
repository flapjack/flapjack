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
    class NotificationR

      include Flapjack::Data::RedisRecord

      # NB can't use has_one associations for the states, as the redis persistence
      # is only transitory (used to trigger a queue pop)
      define_attributes :event_id          => :string,
                        :state_id          => :id,
                        :state_duration    => :integer,
                        :previous_state_id => :id,
                        :severity          => :string,
                        :time              => :timestamp,
                        :duration          => :integer,
                        :tags              => :set

      validate :event_id, :presence => true
      validate :state_id, :presence => true
      validate :state_duration, :presence => true
      validate :severity, :presence => true
      validate :time, :presence => true

      # TODO ensure 'unacknowledged_failures' behaviour is covered

      # query for 'recovery' notification should be for 'ok' state, intersect notified == true
      # query for 'acknowledgement' notification should be 'acknowledgement' state, intersect notified == true
      # any query for 'problem', 'critical', 'warning', 'unknown' notification should be
      # for union of 'critical', 'warning', 'unknown' states, intersect notified == true

      def self.severity_for_state(state, max_notified_severity)
        if ([state, max_notified_severity] & ['critical', 'test_notifications']).any?
          'critical'
        elsif [state, max_notified_severity].include?('warning')
          'warning'
        elsif [state, max_notified_severity].include?('unknown')
          'unknown'
        else
          'ok'
        end
      end

      def self.push(queue, notification)
        notif_json = nil

        begin
          notif_json = notification.as_json.to_json
        rescue Oj::Error => e
          # if opts[:logger]
          #   opts[:logger].warn("Error serialising notification json: #{e}, notification: #{notif.inspect}")
          # end
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
            # if opts[:logger]
            #   opts[:logger].warn("Error deserialising notification json: #{e}, raw json: #{notif_json.inspect}")
            # end
            notification = nil
          end

          next unless notification

          # TODO tags must be a Set -- convert, or ease that restriction
          symbolized_notificiation = notification.inject({}) {|m,(k,v)| m[k.to_sym] = v; m}
          yield self.new(symbolized_notificiation) if block_given?
        end
      end

      def self.wait_for_queue(queue)
        Flapjack.redis.brpop("#{queue}_actions")
      end

      def contents
        notification_type = case event.type
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

        prev_state = self.previous_state_id ? Flapjack::Data::CheckStateR.load(previous_state_id) : nil
        state      = self.state_id ? Flapjack::Data::CheckStateR.load(state_id) : nil

        {'state'             => (state ? state.state : nil),
         'summary'           => (state ? state.summary : nil),
         'details'           => (state ? state.details : nil),
         'count'             => (state ? state.count : nil),
         'last_state'        => (prev_state ? prev_state.state : nil),
         'last_summary'      => (prev_state ? prev_state.summary : nil),
         'event_id'          => self.event_id,
         'severity'          => self.severity,
         'duration'          => self.duration,
         'state_duration'    => self.state_duration,
         'time'              => self.time,
         'tags'              => self.tags,
         'notification_type' => notification_type
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
            "event_id: \"#{@event_id}\" state: #{@state} event_tags: #{@tags.to_json} media: #{media.inspect}"
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
                rule.is_occurring_now?(:contact => contact, :default_timezone => default_timezone)
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
                                          :state => @state)
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

    end
  end
end
