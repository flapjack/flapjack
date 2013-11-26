#!/usr/bin/env ruby

# 'Notification' refers to the template object created when an event occurs,
# from which individual 'Message' objects are created, one for each
# contact+media recipient.

require 'sandstorm/record'

require 'flapjack/data/alert'
require 'flapjack/data/contact'

module Flapjack
  module Data
    class Notification

      include Sandstorm::Record

      attr_accessor :logger

      # NB can't use has_one associations for the states, as the redis persistence
      # is only transitory (used to trigger a queue pop)
      define_attributes :state_duration    => :integer,
                        :severity          => :string,
                        :type              => :string,
                        :time              => :timestamp,
                        :duration          => :integer,
                        :tags              => :set

      belongs_to :entity_check, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :notifications

      # state association will not be set for notification tests
      belongs_to :state, :class_name => 'Flapjack::Data::CheckState',
        :inverse_of => :current_notifications
      belongs_to :previous_state, :class_name => 'Flapjack::Data::CheckState',
        :inverse_of => :previous_notifications

      validate :state_duration, :presence => true
      validate :severity, :presence => true
      validate :type, :presence => true
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

      def state_or_ack
        case self.type
        when 'acknowledgement', 'test'
          self.type
        else
          self.state ? self.state.state : nil
        end
      end

      def alerts(contacts, opts = {})
        return [] if contacts.nil? || contacts.empty?

        default_timezone = opts[:default_timezone]
        check = self.entity_check

        alerts_for_contacts = []

        contacts.each do |contact|
          media_to_use = media_for_contact(contact, :entity_check => check,
            :default_timezone => default_timezone)
          next if media_to_use.nil? || media_to_use.empty?

          media_to_use.each do |medium|
            alert = alert_for_medium(medium, :entity_check => check)
            next if alert.nil?
            alerts_for_contacts << alert
          end
        end

        alerts_for_contacts
      end

      def log_rules(rules, description)
        return if logger.nil?
        logger.debug "#{rules.length} matching rules remain after #{description}:"
          rules.each do |rules|
          logger.debug "  - #{rule.to_json}"
        end
      end

      # return value may or may not be a Sandstorm association; i.e. collect,
      # each, etc. methods may be used on its contained values. if nil is
      # returned that value will be compacted away.
      def media_for_contact(contact, opts = {})
        contact_id = contact.id
        rules = contact.notification_rules
        media = contact.media

        return media if rules.empty?

        entity_check = opts[:entity_check]
        entity_name = entity_check.entity_name
        check_name  = entity_check.name

        log_rules(rules, "initial")

        matchers = rules.select do |rule|
          (rule.match_entity?(entity_check.entity_name) ||
           rule.match_tags?(self.tags) || !rule.is_specific?) &&
          rule.is_occurring_now?(:contact => contact,
            :default_timezone => opts[:default_timezone])
        end

        log_rules(matchers, "after time, entity and tags") if matchers.count != rules.count

        # delete any general matchers if there are more specific matchers left
        if matchers.any? {|matcher| matcher.is_specific? }
          num_matchers = matchers.count
          matchers.reject! {|matcher| !matcher.is_specific? }

          log_rules(matchers, "after remove general if specific exist") if matchers.count != rules.count
        end

        # delete media based on blackholes
        blackhole_matchers = matchers.map {|matcher| matcher.blackhole?(self.severity) ? matcher : nil }.compact
        if blackhole_matchers.length > 0
          log_rules(blackhole_matchers, "#{blackhole_matchers.count} blackhole matchers found - skipping")
          return
        elsif !logger.nil?
          logger.debug "no blackhole matchers matched"
        end

        rule_media = matchers.inject(Set.new) {|memo, matcher|
          med_sev = matcher.media_for_severity(self.severity)
          next memo if med_sev.nil?
          memo += med_sev
        }

        unless logger.nil?
          logger.debug "collected media_for_severity(#{self.severity}): #{rule_media.inspect}"
        end

        final_media = rule_media.inject([]) {|memo, media_type|
          medium = media.intersect(:type => media_type).all.first
          next memo if medium.nil? ||
            medium.drop_notifications?(:entity_check => entity_check,
                                       :state => state_or_ack)

          memo << medium
          memo
        }

        unless logger.nil?
          logger.debug "media after contact_drop?: #{final_media.collect(&:type)}"
        end

        return if final_media.empty?
        final_media
      end

      def alert_for_medium(medium, opts = {})
        rollup_type = nil
        media_type  = medium.type

        unless logger.nil?
          logger.debug("using media #{media_type}")
        end

        entity_check = opts[:entity_check]

        unless (['ok', 'acknowledgement', 'test'].include?(state_or_ack)) ||
          medium.alerting_checks.exists?(entity_check.id)

          medium.alerting_checks << entity_check
        end

        # expunge checks in (un)scheduled maintenance from the alerting set
        cleaned = medium.clean_alerting_checks
        unless logger.nil?
          logger.debug("cleaned alerting checks for #{media_type}: #{cleaned}")
        end

        alerting_checks_count = medium.alerting_checks.count
        unless logger.nil?
          logger.debug("current alerting checks for #{media_type}: #{alerting_checks_count}")
        end

        unless medium.rollup_threshold.nil?
          if alerting_checks_count >= medium.rollup_threshold
            if medium.drop_notifications?(:rollup => true)
              unless logger.nil?
                logger.debug("dropping notifications as medium blocked")
              end
              return
            end

            medium.update_sent_alert_keys(:rollup => true,
              :delete => (['ok', 'acknowledgement'].include?(state_or_ack)))
            rollup_type = 'problem'
          elsif (alerting_checks_count + cleaned) >= medium.rollup_threshold
            # alerting checks was just cleaned such that it is now below the rollup threshold
            rollup_type = 'recovery'
          end
        end

        unless logger.nil?
          logger.debug "rollup decisions: #{entity_name}:#{check_name} " +
            "#{state_or_ack} #{media_type} #{medium.address} " +
            "rollup_type: #{rollup_type}"
        end

        alert = Flapjack::Data::Alert.new(:state => self.state_or_ack,
          :rollup => rollup_type, :state_duration => self.state_duration,
          :acknowledgement_duration => duration,
          :notification_type => self.type)
        unless alert.save
          raise "Couldn't save alert: #{alert.errors.full_messages.inspect}"
        end

        medium.alerts << alert
        entity_check.alerts << alert

        alert
      end

    end
  end
end
