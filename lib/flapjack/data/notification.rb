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


    def alerts_for(route_ids_by_contact_id, opts = {})
      logger = opts[:logger]

      transports = opts[:transports]

      timestamp = opts[:timestamp]
      default_timezone = opts[:default_timezone]
      safe_state_or_ack = self.state_or_ack

      notification_state = self.state ? self.state.state : nil

      alert_check = self.check

      logger.info "contacts: #{route_ids_by_contact_id.keys.size}"

      contacts = route_ids_by_contact_id.empty? ? [] :
        Flapjack::Data::Contact.find_by_ids(*route_ids_by_contact_id.keys)
      return [] if contacts.empty?

      # TODO pass in base time from outside (cast to zone per contact), so
      # all alerts from this notification use a consistent time

      contact_ids_to_drop = []

      route_ids = contacts.inject([]) do |memo, contact|
        routes = Flapjack::Data::Route.find_by_ids(*route_ids_by_contact_id[contact.id])
        next memo if routes.empty?

        timezone = contact.time_zone(:default => default_timezone)
        routes = routes.select {|route| route.is_occurring_now?(timezone) }

        contact_ids_to_drop << contact.id if routes.any? {|r| r.drop }

        memo += routes.map(&:id)
        memo
      end

      logger.info "routes after time: #{route_ids.size}"
      return [] if route_ids.empty?

      route_ids -= contact_ids_to_drop.flat_map {|c_id| route_ids_by_contact_id[c_id] }

      logger.info "routes after drop: #{route_ids.size}"
      return [] if route_ids.empty?

      Flapjack::Data::Medium.lock(Flapjack::Data::Check,
                                  Flapjack::Data::ScheduledMaintenance,
                                  Flapjack::Data::UnscheduledMaintenance,
                                  Flapjack::Data::Route,
                                  Flapjack::Data::Alert,
                                  Flapjack::Data::Medium,
                                  Flapjack::Data::Contact) do

        media_ids_by_route_id = Flapjack::Data::Route.intersect(:id => route_ids).
          associated_ids_for(:media)

        media_ids = Set.new(media_ids_by_route_id.values).flatten.to_a

        logger.info "media from routes: #{media_ids.size}"

        alertable_media = Flapjack::Data::Medium.intersect(:id => media_ids,
          :transport => transports).all

        # we want to consider this as 'alerting' for the purpose of rollup
        # calculations, if it's failing, even if we won't notify on this media
        this_notification_failure = Flapjack::Data::CheckState.failing_states.include?(safe_state_or_ack) &&
          !(alert_check.in_scheduled_maintenance? || alert_check.in_unscheduled_maintenance?)

        ok_states = Flapjack::Data::CheckState.ok_states + ['acknowledgement']

        this_notification_ok      = ok_states.include?(safe_state_or_ack)
        is_a_test                 = 'test'.eql?(safe_state_or_ack)

        alert_check.alerting_media.add(*alertable_media) if this_notification_failure

        logger.info "pre-media test: \n" \
          "  this_notification_failure = #{this_notification_failure}\n" \
          "  this_notification_ok      = #{this_notification_ok}\n" \
          "  is_a_test                 = #{is_a_test}"

        alertable_media.each_with_object([]) do |medium, memo|

          logger.info "media test: #{medium.transport}, #{medium.id}"

          no_previous_notification  = medium.last_notification.nil?

          last_notification_failure = Flapjack::Data::CheckState.failing_states.
             include?(medium.last_notification_state)
          last_notification_ok      = ok_states.include?(medium.last_notification_state)

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

          interval_allows = medium.last_notification.nil? ||
            ((last_notification_failure && this_notification_failure) &&
             ((medium.last_notification + medium.interval) < timestamp))

          logger.info "  last_notification_failure = #{last_notification_failure}\n" \
            "  last_notification_ok      = #{last_notification_ok}" \
            "  interval_allows  = #{interval_allows}\n" \
            "  alert_rollup , last_rollup_type = #{alert_rollup} , #{medium.last_rollup_type}\n" \
            "  safe_state_or_ack , last_notification_state  = #{safe_state_or_ack} , #{medium.last_notification_state}\n" \
            "  no_previous_notification  = #{no_previous_notification}\n"

          next unless is_a_test || no_previous_notification ||
              (last_notification_failure && this_notification_ok) ||
            (alert_rollup != medium.last_rollup_type) ||
            (safe_state_or_ack != medium.last_notification_state) ||
            interval_allows

          alert = Flapjack::Data::Alert.new(:state => safe_state_or_ack,
            :state_duration => self.state_duration,
            :acknowledgement_duration => self.duration,
            :notification_type => self.type,
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
            medium.last_notification       = timestamp
            medium.last_notification_state = safe_state_or_ack
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
