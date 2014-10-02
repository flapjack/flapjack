#!/usr/bin/env ruby

# 'Notification' refers to the template object created when an event occurs,
# from which individual 'Message' objects are created, one for each
# contact+media recipient.

require 'sandstorm/records/redis_record'

require 'flapjack/data/alert'
require 'flapjack/data/contact'

module Flapjack
  module Data
    class Notification

      include Sandstorm::Records::RedisRecord

      attr_accessor :logger

      # NB can't use has_one associations for the states, as the redis persistence
      # is only transitory (used to trigger a queue pop)
      define_attributes :state_duration => :integer,
                        :severity       => :string,
                        :type           => :string,
                        :time           => :timestamp,
                        :duration       => :integer,
                        :event_hash     => :string

      belongs_to :check, :class_name => 'Flapjack::Data::Check',
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
      validate :event_hash, :presence => true

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
          st = self.state
          st ? st.state : nil
        end
      end

      # TODO move this and related methods to 'notifier.rb'
      def alerts(opts = {})
        @logger = opts[:logger]

        default_timezone = opts[:default_timezone]
        safe_state_or_ack = self.state_or_ack

        alert_check = self.check

        # candidate rules are all rules for which
        #   (rule.tags.ids - check.tags.ids).empty?
        # this includes generic rules, i.e. ones with no tags

        # NB -- this logic will be a good candidate for having the result be
        # cached, and regenerated any time check tags or notification rule
        # tags change

        # A generic rule in Flapjack v2 means that it applies to all checks, not
        # just all checks the contact is separately regeistered for, as in v1.
        # These are not automatically created for users any more, but can be
        # deliberately configured.
        generic_rules_ids = Flapjack::Data::NotificationRule.intersect(:is_specific => false).ids

        tags_ids = alert_check.tags.ids
        tag_notification_rules_ids = Flapjack::Data::Tag.associated_ids_for_notification_rules(*tags_ids.to_a)

        notification_rules_ids = Set.new(tag_notification_rules_ids.values).flatten | generic_rules_ids
        notification_rule_drops_ids = Flapjack::Data::NotificationRule.
                                        associated_ids_for_drops(*notification_rules_ids)

        dropped_nr_ids = Flapjack::Data::NotificationRuleDrop.
          intersect(:id => notification_rule_drops_ids).map(&:notification_rule_id)

        after_blackhole_nr_ids = notification_rules_ids - blackholed_nr_ids

        return [] if after_blackhole_nr_ids.empty?

        after_blackhole_nrules = Flapjack::Data::NotificationRule.find_by_ids(*after_blackhole_nr_ids)

        # TODO build hash of rule by id

        contact_ids = Flapjack::Data::NotificationRule.
                        associated_ids_for_contact(*after_blackhole_nr_ids.to_a)

        abnr_ids_by_contact_id = contact_ids.inject({}) do |memo, (nr_id, c_id)|
          memo[c_id] ||= []
          memo[c_id] << nr_id # set this to rule instead of id, useful in loop
          memo
        end

        contacts = abnr_ids_by_contact_id.empty? ? [] :
          Flapjack::Data::Contact.find_by_ids(*abnr_ids_by_contact_id.keys)

        return [] if contacts.empty?

        # TODO pass in base time from outside (cast to zone per contact), so
        # all alerts from this notification use a consistent time

        contacts.inject([]) do |memo, contact|
          matchers = after_blackhole_nrules.select do |nr|
            abnr_ids_by_contact_id[contact.id].include?(nr.id)
          end

          log_rules(matchers, "initial")

          # delete any general matchers if there are more specific matchers left
          generic = matchers.reject {|matcher| matcher.is_specific }

          unless generic.empty? || (generic.size == matchers.size)
            matchers = matchers - generic

            log_rules(matchers, "after remove general if specific exist")
          end

          next memo if matchers.empty?

          rule_count = matchers.size
          timezone = contact.time_zone(:default => default_timezone)
          matchers = matchers.select {|rule| rule.is_occurring_now?(timezone) }
          log_rules(matchers, "after time and tags") if matchers.size != rule_count

          next memo if matchers.empty?

          Flapjack::Data::Medium.lock(Flapjack::Data::Check,
                                      Flapjack::Data::ScheduledMaintenance,
                                      Flapjack::Data::UnscheduledMaintenance,
                                      Flapjack::Data::NotificationRuleRoute,
                                      Flapjack::Data::NotificationBlock,
                                      Flapjack::Data::Alert) do

            # media_to_use = media_for_contact(contact, matchers, :check => alert_check)

            route_ids = Flapjack::Data::NotificationRule.associated_ids_for_routes(*matchers.map(&:id))

            routes = Flapjack::Data::NotificationRuleRoute.intersect(:ids => route_ids,
              :state => [nil, safe_state_or_ack])

            rule_media = routes.media

            # unless logger.nil?
            #   logger.debug "collected media_for_severity(#{self.severity}): #{rule_media.inspect}"
            # end

            final_media = rule_media.reject {|medium|
              medium.drop_notifications?(:check => alert_check,
                                         :state => safe_state_or_ack)
            }

            # unless logger.nil?
            #   logger.debug "media after contact_drop?: #{final_media.collect(&:type)}"
            # end

            next memo if final_media.empty?

            final_media.each do |medium|
              alert = alert_for_medium(medium, :check => alert_check, :state => safe_state_or_ack)
              next if alert.nil?
              memo << alert
            end
          end

          memo
        end
      end

      def log_rules(rules, description)
        return if logger.nil?
        logger.debug "#{rules.count} matching rules remain after #{description}:"
        rules.each do |rule|
          logger.debug "  - #{rule.inspect}"
          # rule.states.each do |rule_state|
          #   logger.debug "  - #{rule_state.inspect}"
          # end
        end
      end

      def alert_for_medium(medium, opts = {})
        rollup_type = nil
        media_type  = medium.type

        unless logger.nil?
          logger.debug("using media #{media_type}")
        end

        alert_check = opts[:check]

        unless (['ok', 'acknowledgement', 'test'].include?(opts[:state])) ||
          medium.alerting_checks.exists?(alert_check.id)

          medium.alerting_checks << alert_check
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
              :delete => (['ok', 'acknowledgement'].include?(opts[:state])))
            rollup_type = 'problem'
          elsif (alerting_checks_count + cleaned) >= medium.rollup_threshold
            # alerting checks was just cleaned such that it is now below the rollup threshold
            medium.update_sent_alert_keys(:rollup => true, :delete => true)
            rollup_type = 'recovery'
          end
        end

        unless logger.nil?
          logger.debug "rollup decisions: #{alert_check.name} " +
            "#{opts[:state]} #{media_type} #{medium.address} " +
            "rollup_type: #{rollup_type}"
        end

        alert = Flapjack::Data::Alert.new(:state => opts[:state],
          :rollup => rollup_type, :state_duration => self.state_duration,
          :acknowledgement_duration => duration,
          :notification_type => self.type)
        unless alert.save
          raise "Couldn't save alert: #{alert.errors.full_messages.inspect}"
        end

        medium.alerts << alert
        alert_check.alerts << alert

        alert
      end

    end
  end
end
