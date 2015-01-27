#!/usr/bin/env ruby

# 'Notification' refers to the template object created when an event occurs,
# from which individual 'Message' objects are created, one for each
# contact+media recipient.

require 'zermelo/records/redis_record'

require 'flapjack/data/alert'
require 'flapjack/data/contact'

module Flapjack
  module Data
    class Notification

      include Zermelo::Records::RedisRecord

      define_attributes :severity       => :string,
                        :duration       => :integer,
                        :condition_duration => :float,
                        :event_hash     => :string

      belongs_to :entry, :class_name => 'Flapjack::Data::Entry',
        :inverse_of => :notification

      validates :severity,
        :inclusion => {:in => Flapjack::Data::Condition.unhealthy.keys +
                              Flapjack::Data::Condition.healthy.keys }

      # query for 'recovery' notification should be for 'ok' state, intersect notified == true
      # query for 'acknowledgement' notification should be 'acknowledgement' state, intersect notified == true
      # any query for 'problem', 'critical', 'warning', 'unknown' notification should be
      # for union of 'critical', 'warning', 'unknown' states, intersect notified == true

      def alerts_for(alert_check, opts = {})
        in_sched   = alert_check.in_scheduled_maintenance?
        in_unsched = alert_check.in_unscheduled_maintenance?

        rule_ids_by_contact_id, route_ids_by_rule_id =
          alert_check.rule_ids_and_route_ids(:severity => self.severity)

        notification_entry = self.entry
        notification_state = notification_entry.state

        if rule_ids_by_contact_id.empty?
          alert_type = Flapjack::Data::Alert.notification_type(notification_entry.action,
            notification_entry.condition)

          Flapjack.logger.info { "#{alert_check.name} | #{alert_type} | NO RULES" }
          return
        end

        transports = opts[:transports]

        default_timezone = opts[:default_timezone]

        Flapjack.logger.info { "contact_ids: #{rule_ids_by_contact_id.keys.size}" }

        contacts = rule_ids_by_contact_id.empty? ? [] :
          Flapjack::Data::Contact.find_by_ids(*rule_ids_by_contact_id.keys)
        return if contacts.empty?

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

        Flapjack.logger.info "rule_ids after time: #{rule_ids.size}"
        return if rule_ids.empty?

        rule_ids -= contact_ids_to_drop.flat_map {|c_id| rule_ids_by_contact_id[c_id] }

        Flapjack.logger.info "rule_ids after drop: #{rule_ids.size}"
        return if rule_ids.empty?

        Flapjack::Data::Medium.lock(Flapjack::Data::Check,
                                    Flapjack::Data::ScheduledMaintenance,
                                    Flapjack::Data::UnscheduledMaintenance,
                                    Flapjack::Data::Rule,
                                    Flapjack::Data::Alert,
                                    Flapjack::Data::Route,
                                    Flapjack::Data::Notification,
                                    Flapjack::Data::Contact,
                                    Flapjack::Data::State,
                                    Flapjack::Data::Entry) do

          media_ids_by_rule_id = Flapjack::Data::Rule.intersect(:id => rule_ids).
            associated_ids_for(:media)

          media_ids = Set.new(media_ids_by_rule_id.values).flatten.to_a

          Flapjack.logger.info "media from rules: #{media_ids.size}"

          alertable_media = Flapjack::Data::Medium.intersect(:id => media_ids,
            :transport => transports).all

          # we want to consider this as 'alerting' for the purpose of rollup
          # calculations, if it's failing, even if we won't notify on this media

          Flapjack.logger.info "healthy #{Flapjack::Data::Condition.healthy?(notification_state.condition)}"
          Flapjack.logger.info "sched #{in_sched}"
          Flapjack.logger.info "unsched #{in_unsched}"

          this_notification_failure = !(Flapjack::Data::Condition.healthy?(notification_state.condition) ||
            in_sched || in_unsched)

          this_notification_ok = 'acknowledgement'.eql?(notification_entry.action) ||
            Flapjack::Data::Condition.healthy?(notification_state.condition)
          is_a_test            = 'test_notifications'.eql?(notification_entry.action)

          unless is_a_test
            route_ids = route_ids_by_rule_id.values.reduce(:|)
            Flapjack::Data::Route.intersect(:id => route_ids).each do |route|
              route.is_alerting = this_notification_failure
              route.save # no-op if the value didn't change
            end
          end

          Flapjack.logger.info "pre-media test: \n" \
            "  this_notification_failure = #{this_notification_failure}\n" \
            "  this_notification_ok      = #{this_notification_ok}\n" \
            "  is_a_test                 = #{is_a_test}"

          alertable_media.each_with_object([]) do |medium, memo|

            Flapjack.logger.info "media test: #{medium.transport}, #{medium.id}"

            last_entry = medium.last_entry

            last_entry_ok = last_entry.nil? ? nil :
              (Flapjack::Data::Condition.healthy?(last_entry.condition) ||
              'acknowledgement'.eql?(last_entry.action))

            alerting_check_ids = if medium.rollup_threshold.nil? || (medium.rollup_threshold == 0)
              nil
            else
              medium.alerting_checks.map(&:id)
            end

            Flapjack.logger.info " alerting_checks: #{alerting_check_ids.inspect}"

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

            Flapjack.logger.info "last_entry #{last_entry.inspect}"

            interval_allows = last_entry.nil? ||
              ((!last_entry_ok && this_notification_failure) &&
               ((last_entry.timestamp + (medium.interval || 0)) < notification_entry.timestamp))

            Flapjack.logger.info "  last_entry_ok = #{last_entry_ok}\n" \
              "  interval_allows  = #{interval_allows}\n" \
              "  alert_rollup , last_rollup_type = #{alert_rollup} , #{medium.last_rollup_type}\n" \
              "  condition , last_notification_condition  = #{notification_state.condition} , #{last_entry.nil? ? '-' : last_entry.condition}\n" \
              "  no_previous_notification  = #{last_entry.nil?}\n"

            next unless is_a_test || last_entry.nil? ||
                (!last_entry_ok && this_notification_ok) ||
              (alert_rollup != medium.last_rollup_type) ||
              ('acknowledgement'.eql?(last_entry.action) && this_notification_failure) ||
              (notification_state.condition != last_entry.condition) ||
              interval_allows

            alert = Flapjack::Data::Alert.new(:condition => notification_state.condition,
              :action => notification_entry.action,
              :last_condition => (last_entry.nil? ? nil : last_entry.condition),
              :last_action => (last_entry.nil? ? nil : last_entry.action),
              :condition_duration => self.condition_duration,
              :acknowledgement_duration => self.duration,
              :rollup => alert_rollup)

            unless alert_rollup.nil?
              alerting_checks = Flapjack::Data::Check.find_by_ids(*alerting_check_ids)
              alert.rollup_states = alerting_checks.each_with_object({}) do |check, memo|
                cond = check.states.last.condition
                memo[cond] ||= []
                memo[cond] << check.name
              end
            end

            unless alert.save
              raise "Couldn't save alert: #{alert.errors.full_messages.inspect}"
            end

            medium.alerts      << alert
            alert_check.alerts << alert

            Flapjack.logger.info "alerting for #{medium.transport}, #{medium.address}"

            unless 'test_notifications'.eql?(notification_entry.action)
              unless last_entry.nil?
                Flapjack.logger.info "clearing medium #{medium.transport}, #{medium.address} from entry #{last_entry.id}"
                last_entry.latest_media.delete(medium)
                Flapjack.logger.info "pre-delete-check: notification latest_media"
                Flapjack::Data::Entry.delete_if_unlinked(last_entry)
              end
              notification_entry.latest_media.add(medium)
              medium.last_rollup_type = alert.rollup
              medium.save
            end

            memo << alert
          end
        end
      end
    end
  end
end
