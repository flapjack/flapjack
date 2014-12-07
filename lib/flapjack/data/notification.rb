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
      define_attributes :severity       => :string,
                        :time           => :timestamp,
                        :duration       => :integer,
                        :event_hash     => :string

      belongs_to :check, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :notifications

      belongs_to :state, :class_name => 'Flapjack::Data::State',
        :inverse_of => :notifications

      validates :severity, :presence => true
      validates :time, :presence => true
      validates :event_hash, :presence => true

      # TODO ensure 'unacknowledged_failures' behaviour is covered

      # query for 'recovery' notification should be for 'ok' state, intersect notified == true
      # query for 'acknowledgement' notification should be 'acknowledgement' state, intersect notified == true
      # any query for 'problem', 'critical', 'warning', 'unknown' notification should be
      # for union of 'critical', 'warning', 'unknown' states, intersect notified == true

      def alerts_for(rule_ids_by_contact_id, opts = {})
        logger = opts[:logger]

        transports = opts[:transports]

        timestamp = opts[:timestamp]
        default_timezone = opts[:default_timezone]

        notification_state = self.state
        condition = Flapjack::Data::Condition.find_by_id!(notification_state.condition)

        alert_check = notification_state.check

        logger.info { "contact_ids: #{rule_ids_by_contact_id.keys.size}" }

        contacts = rule_ids_by_contact_id.empty? ? [] :
          Flapjack::Data::Contact.find_by_ids(*rule_ids_by_contact_id.keys)
        return [] if contacts.empty?

        # TODO pass in base time from outside (cast to zone per contact), so
        # all alerts from this notification use a consistent time

        contact_ids_to_drop = []

        rule_ids = contacts.inject([]) do |memo, contact|
          rules = Flapjack::Data::Rule.find_by_ids(*rule_ids_by_contact_id[contact.id])
          next memo if rules.empty?

          timezone = contact.time_zone(:default => default_timezone)
          rules.select! {|rule| rule.is_occurring_now?(timezone) }

          contact_ids_to_drop << contact.id if rules.any? {|r| !r.has_media }

          memo += rules.map(&:id)
          memo
        end

        logger.info "rule_ids after time: #{rule_ids.size}"
        return [] if rule_ids.empty?

        rule_ids -= contact_ids_to_drop.flat_map {|c_id| rule_ids_by_contact_id[c_id] }

        logger.info "rule_ids after drop: #{rule_ids.size}"
        return [] if rule_ids.empty?

        Flapjack::Data::Medium.lock(Flapjack::Data::Check,
                                    Flapjack::Data::ScheduledMaintenance,
                                    Flapjack::Data::UnscheduledMaintenance,
                                    Flapjack::Data::Rule,
                                    Flapjack::Data::Alert,
                                    Flapjack::Data::Medium,
                                    Flapjack::Data::Contact) do

          media_ids_by_rule_id = Flapjack::Data::Rule.intersect(:id => rule_ids).
            associated_ids_for(:media)

          media_ids = Set.new(media_ids_by_rule_id.values).flatten.to_a

          logger.info "media from rules: #{media_ids.size}"

          alertable_media = Flapjack::Data::Medium.intersect(:id => media_ids,
            :transport => transports).all

          # we want to consider this as 'alerting' for the purpose of rollup
          # calculations, if it's failing, even if we won't notify on this media

          this_notification_failure = !(condition.healthy ||
            alert_check.in_scheduled_maintenance? ||
            alert_check.in_unscheduled_maintenance?)

          this_notification_ok = 'acknowledgement'.eql?(notification_state.action) || condition.healthy?
          is_a_test            = 'test_notificiations'.eql?(notification_state.action)

          alert_check.alerting_media.add(*alertable_media) if this_notification_failure

          logger.info "pre-media test: \n" \
            "  this_notification_failure = #{this_notification_failure}\n" \
            "  this_notification_ok      = #{this_notification_ok}\n" \
            "  is_a_test                 = #{is_a_test}"

          alertable_media.each_with_object([]) do |medium, memo|

            logger.info "media test: #{medium.transport}, #{medium.id}"

            last_notification = medium.last_notification

            last_notification_condition = last_notification.nil? ? nil :
              Flapjack::Data::Condition.find_by_id!(last_notification.condition)

            last_notification_ok = last_notification.nil? ? nil :
              last_notification_condition.healthy

            alerting_check_ids = medium.rollup_threshold.nil? || (medium.rollup_threshold == 0) ? nil :
                                   medium.alerting_checks.ids

            # TODO remove any alerting checks that aren't in failing_checks,
            # dynamically calculated

            logger.info " alerting_checks: #{alerting_check_ids.inspect}"

            alert_rollup = if alerting_check_ids.nil?
              if 'problem'.eql?(medium.last_rollup_type)
                'recovery'
              else
                nil
              end
            elsif alerting_check_ids.size >= medium.rollup_threshold
              'problem'
            elsif 'problem'.eql?(medium.last_rollup_type)
              'recovery'
            else
              nil
            end

            interval_allows = last_notification.nil? ||
              ((!last_notification_ok && this_notification_failure) &&
               ((last_notification.timestamp + medium.interval) < timestamp))

            logger.info "  last_notification_ok = #{last_notification_ok}\n" \
              "  interval_allows  = #{interval_allows}\n" \
              "  alert_rollup , last_rollup_type = #{alert_rollup} , #{medium.last_rollup_type}\n" \
              "  condition , last_notification_condition  = #{condition.id} , #{last_notification_condition.nil? ? '-' : last_notification_condition.id}\n" \
              "  no_previous_notification  = #{last_notification.nil?}\n"

            next unless is_a_test || last_notification.nil? ||
                (!last_notification_ok && this_notification_ok) ||
              (alert_rollup != medium.last_rollup_type) ||
              (condition.id != last_notification_condition.id) ||
              interval_allows

            alert = Flapjack::Data::Alert.new(:state => (notification_state.action || notification_state.condition),
              :condition_duration => self.condition_duration,
              :acknowledgement_duration => self.duration,
              :rollup => alert_rollup)

            unless alert_rollup.nil?
              alerting_checks = Flapjack::Data::Check.find_by_ids(*alerting_check_ids)
              alert.rollup_states = alerting_checks.each_with_object({}) do |check, memo|
                memo[check.state] ||= []
                memo[check.state] << check.name
              end
            end

            unless alert.save
              raise "Couldn't save alert: #{alert.errors.full_messages.inspect}"
            end

            medium.alerts      << alert
            alert_check.alerts << alert

            logger.info "alerting with:"
            logger.info alert.inspect

            unless 'test'.eql?(safe_state_or_ack)
              medium.last_notification_state = notification_state
              medium.last_rollup_type        = alert.rollup
              medium.save
            end

            memo << alert
          end
        end
      end
    end
  end
end
