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
require 'flapjack/data/rollup_alert'

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

      in_unscheduled_maintenance = check.in_scheduled_maintenance?
      in_scheduled_maintenance   = check.in_unscheduled_maintenance?

      alerts.each do |alert|
        medium = alert.medium
        unless @queues.has_key?(medium.type)
          # TODO when notification code is moved up here, do this test before the
          # alert is generated
          @logger.error("no queue for media type: #{medium.type}")
          next
        end

        address = medium.address

        @notifylog.info("#{check_name} | " +
          "#{notification.type} | #{medium.contact.id} | #{medium.type} | #{medium.address}")

        @logger.info("Enqueueing #{medium.type} alert for " +
          "#{check_name} to #{medium.address} " +
          " type: #{notification.type} rollup: #{alert.rollup || '-'}")

        Flapjack::Data::Check.lock(Flapjack::Data::CheckState,
          Flapjack::Data::Alert, Flapjack::Data::RollupAlert) do

          medium.alerting_checks.each do |alert_check|
            last_state  = alert_check.states.last
            last_change = last_state.nil? ? nil : last_state.timestamp.to_i

            rollup_alert = Flapjack::Data::RollupAlert.new(
              :state    => (last_state ? last_state.state : nil),
              :duration => (last_change ? (Time.now.to_i - last_change) : nil))
            rollup_alert.save
            alert.rollup_alerts << rollup_alert
            alert_check.rollup_alerts << rollup_alert
          end

        end

        if ['recovery', 'acknowledgement'].include?(notification.type)

          ['warning', 'critical', 'unknown'].each do |alert_state|
            medium.update_sent_alert_keys(
              :check => check,
              :state => alert_state,
              :delete => true)
          end
        elsif notification.state
          medium.update_sent_alert_keys(
            :check => check,
            :state => notification.state.state)
        end

        # # Alert tags aren't set properly, I think
        # contents_tags = contents['tags']
        # contents['tags'] = contents_tags.is_a?(Set) ? contents_tags.to_a : contents_tags

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
      tag_rules_ids = Flapjack::Data::Tag.associated_ids_for_rules(*tags_ids.to_a)
      unified_tag_ids = Set.new(tag_rules_ids.values).flatten
      rule_tags_ids = Flapjack::Data::Rule.associated_ids_for_tags(*(unified_tag_ids.to_a))
      rule_tags_ids.delete_if {|rid, tids| (tids - tags_ids).size > 0 }

      return [] if (rule_tags_ids.empty? && generic_rules_ids.empty?)

      rules_ids = rule_tags_ids.keys | generic_rules_ids.to_a

      logger.info "Matching rules: #{rules_ids.size}"

      return [] if rules_ids.empty?

      rule_route_ids = Flapjack::Data::Rule.associated_ids_for_routes(*rules_ids)

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
      rule_ids_by_route_id = Flapjack::Data::Route.associated_ids_for_rule(*active_route_ids)

      unified_rule_ids = Set.new(rule_ids_by_route_id.values).flatten

      contact_ids_by_rule_id = Flapjack::Data::Rule.associated_ids_for_contact(*(unified_rule_ids.to_a))

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
                                  Flapjack::Data::NotificationBlock,
                                  Flapjack::Data::Alert) do

        media_ids_by_route_id = Flapjack::Data::Route.associated_ids_for_media(*route_ids)

        media_ids = Set.new(media_ids_by_route_id.values).flatten

        logger.info "media from routes: #{media_ids.size}"

        final_media = Flapjack::Data::Medium.find_by_ids(*(media_ids.to_a)).reject do |medium|
          !medium.last_notification.nil? &&
            ((medium.last_notification + medium.interval) >= timestamp)
        end

        logger.info "media after interval check: #{final_media.size}"

        final_media.collect do |medium|
          alert = medium.alert(notification, :state => safe_state_or_ack)

          medium.alerts << alert
          alert_check.alerts << alert

          alert
        end
      end
    end

  end
end
