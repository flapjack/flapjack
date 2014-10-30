#!/usr/bin/env ruby

require 'active_support/time'

require 'flapjack/exceptions'
require 'flapjack/redis_proxy'
require 'flapjack/record_queue'
require 'flapjack/utility'

require 'flapjack/data/alert'
require 'flapjack/data/check'
require 'flapjack/data/contact'
require 'flapjack/data/event'
require 'flapjack/data/notification'

module Flapjack

  class Notifier

    include Flapjack::Utility

    def initialize(opts = {})
      @lock = opts[:lock]
      @config = opts[:config] || {}
      @logger = opts[:logger]

      @queue = Flapjack::RecordQueue.new(@config['queue'] || 'notifications',
                 Flapjack::Data::Notification)

      queue_configs = @config.find_all {|k, v| k =~ /_queue$/ }
      @queues = Hash[queue_configs.map {|k, v|
        [k[/^(.*)_queue$/, 1], Flapjack::RecordQueue.new(v, Flapjack::Data::Alert)]
      }]

      notify_logfile  = @config['notification_log_file'] || 'log/notify.log'
      unless File.directory?(File.dirname(notify_logfile))
        puts "Parent directory for log file '#{notify_logfile}' doesn't exist"
        puts "Exiting!"
        exit
      end
      @notifylog = ::Logger.new(notify_logfile)
      @notifylog.formatter = proc do |severity, datetime, progname, msg|
        "#{datetime.to_s} | #{msg}\n"
      end

      tz = nil
      tz_string = @config['default_contact_timezone'] || ENV['TZ'] || 'UTC'
      begin
        tz = ActiveSupport::TimeZone.new(tz_string.untaint)
      rescue ArgumentError
        logger.error("Invalid timezone string specified in default_contact_timezone or TZ (#{tz_string})")
        exit 1
      end
      @default_contact_timezone = tz
    end

    def start
      begin
        Sandstorm.redis = Flapjack.redis

        loop do
          @lock.synchronize do
            @queue.foreach {|notif| process_notification(notif) }
          end

          @queue.wait
        end
      ensure
        Flapjack.redis.quit
      end
    end

    def stop_type
      :exception
    end

  private

    # takes an event for which messages should be generated, works out the type of
    # notification, updates the notification history in redis, generates the
    # notifications
    def process_notification(notification)
      @logger.debug ("Processing notification: #{notification.inspect}")

      timestamp   = Time.now
      check       = notification.check
      check_name  = check.name

      routes_by_contact_id = self.class.routes_for(:check => check,
        :severity => notification.severity, :logger => @logger)

      if routes_by_contact_id.empty?
        @logger.debug("No routes for '#{check_name}'")
        @notifylog.info("#{check_name} | #{notification.type} | NO ROUTES")
        return
      end

      alerts = self.class.alerts_for(notification, routes_by_contact_id,
        :check => check, :timestamp => timestamp,
        :default_timezone => @default_contact_timezone, :logger => @logger)

      @logger.info "alerts: #{alerts.size}"

      alerts.each do |alert|
        medium = alert.medium
        unless @queues.has_key?(medium.type)
          # TODO when notification code is moved up here, do this test before the
          # alert is generated
          @logger.error("no queue for media type: #{medium.type}")
          next
        end

        @notifylog.info("#{check_name} | " +
          "#{notification.type} | #{medium.contact.id} | #{medium.type} | #{medium.address}")

        @logger.info("Enqueueing #{medium.type} alert for " +
          "#{check_name} to #{medium.address} " +
          " type: #{notification.type} rollup: #{alert.rollup || '-'}")

        @queues[medium.type].push(alert)
      end
    end

    def self.routes_for(opts = {})
      severity    = opts[:severity]
      alert_check = opts[:check]

      logger = opts[:logger]

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
      generic_rules_ids = Flapjack::Data::Rule.intersect(:is_specific => false).ids

      logger.info "Generic rules: #{generic_rules_ids.size}"

      tags_ids = alert_check.tags.ids

      tag_rules_ids = Flapjack::Data::Tag.intersect(:id => tags_ids).
        associated_ids_for(:rules)

      all_rules_for_tags_ids = Set.new(tag_rules_ids.values).flatten

      rule_tags_ids = Flapjack::Data::Rule.intersect(:id => all_rules_for_tags_ids).
        associated_ids_for(:tags)

      rule_tags_ids.delete_if {|rid, tids| (tids - tags_ids).size > 0 }

      return [] if (rule_tags_ids.empty? && generic_rules_ids.empty?)

      rules_ids = rule_tags_ids.keys | generic_rules_ids.to_a

      logger.info "Matching rules: #{rules_ids.size}"

      return [] if rules_ids.empty?

      rule_route_ids = Flapjack::Data::Rule.intersect(:id => rules_ids).
        associated_ids_for(:routes)

      return [] if rule_route_ids.empty?

      # unrouted rules should be dropped
      rule_route_ids.delete_if {|nr_id, route_ids| route_ids.empty? }
      return [] if rule_route_ids.empty?

      # we only want routes for any state or for the current one
      route_ids_for_all_states = Set.new(rule_route_ids.values).flatten

      # TODO sandstorm should accept a set as well as an array in intersect
      active_route_ids = Flapjack::Data::Route.
        intersect(:id => route_ids_for_all_states.to_a, :state => [nil, severity]).ids

      logger.info "Matching routes: #{active_route_ids.size}"

      return [] if active_route_ids.empty?

      # if more than one route exists for a rule & state, media will be unioned together
      # (may happen with, e.g. overlapping time restrictions, multiple matching rules, etc.)

      # TODO is it worth doing a shortcut check here -- if no media for routes, return [] ?

      # TODO possibly invert the returned data from associated_ids_for belongs_to?
      # we're always doing it on this side anyway
      rule_ids_by_route_id = Flapjack::Data::Route.intersect(:id => active_route_ids).
        associated_ids_for(:rule)

      unified_rule_ids = Set.new(rule_ids_by_route_id.values).flatten

      contact_ids_by_rule_id = Flapjack::Data::Rule.intersect(:id => unified_rule_ids).
        associated_ids_for(:contact)

      rule_ids_by_route_id.inject({}) do |memo, (route_id, rule_id)|
        memo[contact_ids_by_rule_id[rule_id]] ||= []
        memo[contact_ids_by_rule_id[rule_id]] << route_id
        memo
      end
    end

    def self.alerts_for(notification, route_ids_by_contact_id, opts = {})
      logger = opts[:logger]

      timestamp = opts[:timestamp]
      default_timezone = opts[:default_timezone]
      safe_state_or_ack = notification.state_or_ack

      notification_state = notification.state ? notification.state.state : nil

      alert_check = opts[:check]

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

        alertable_media = Flapjack::Data::Medium.find_by_ids(*media_ids)

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

          logger.info "media test: #{medium.type}, #{medium.id}"

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
            ((medium.last_notification + medium.interval) < timestamp)

          logger.info "  last_notification_failure = #{last_notification_failure}\n" \
            "  last_notification_ok      = #{last_notification_ok}" \
            "  interval_allows  = #{interval_allows}\n" \
            "  alert_rollup , last_rollup_type = #{alert_rollup} , #{medium.last_rollup_type}\n" \
            "  safe_state_or_ack , last_notification_state  = #{safe_state_or_ack} , #{medium.last_notification_state}\n" \
            "  no_previous_notification  = #{no_previous_notification}\n"

          next unless is_a_test || no_previous_notification ||
              ((last_notification_failure && this_notification_ok) ||
               (last_notification_ok && this_notification_failure)) ||
            (alert_rollup != medium.last_rollup_type) ||
            (safe_state_or_ack != medium.last_notification_state) ||
            interval_allows

          alert = Flapjack::Data::Alert.new(:state => safe_state_or_ack,
            :state_duration => notification.state_duration,
            :acknowledgement_duration => notification.duration,
            :notification_type => notification.type,
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
