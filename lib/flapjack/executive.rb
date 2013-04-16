#!/usr/bin/env ruby

require 'log4r'
require 'log4r/outputter/fileoutputter'
require 'tzinfo'
require 'active_support/time'

require 'flapjack/filters/acknowledgement'
require 'flapjack/filters/ok'
require 'flapjack/filters/scheduled_maintenance'
require 'flapjack/filters/unscheduled_maintenance'
require 'flapjack/filters/detect_mass_client_failures'
require 'flapjack/filters/delays'
require 'flapjack/data/contact'
require 'flapjack/data/entity_check'
require 'flapjack/data/notification'
require 'flapjack/data/event'
require 'flapjack/redis_pool'
require 'flapjack/utility'

require 'flapjack/gateways/email'
require 'flapjack/gateways/sms_messagenet'

module Flapjack

  class Executive

    include Flapjack::Utility

    def initialize(opts = {})
      @config = opts[:config]
      @redis_config = opts[:redis_config]
      @logger = opts[:logger]
      @redis = Flapjack::RedisPool.new(:config => @redis_config, :size => 2) # first will block

      @queues = {:email     => @config['email_queue'],
                 :sms       => @config['sms_queue'],
                 :jabber    => @config['jabber_queue'],
                 :pagerduty => @config['pagerduty_queue']}

      notifylog  = @config['notification_log_file'] || 'log/notify.log'
      if not File.directory?(File.dirname(notifylog))
        puts "Parent directory for log file #{notifylog} doesn't exist"
        puts "Exiting!"
        exit
      end
      @notifylog = Log4r::Logger.new("executive")
      @notifylog.add(Log4r::FileOutputter.new("notifylog", :filename => notifylog))

      tz_string = @config['default_contact_timezone'] || ENV['TZ'] || 'UTC'
      begin
        tz = ::TZInfo::Timezone.new(tz_string)
      rescue ::TZInfo::InvalidTimezoneIdentifier
        logger.error("Invalid timezone string specified in default_contact_timezone or TZ (#{tz_string})")
        exit 1
      end
      @default_contact_timezone = tz.identifier

      # FIXME: Put loading filters into separate method
      # FIXME: should we make the filters more configurable by the end user?
      options = { :log => opts[:logger], :persistence => @redis }
      @filters = []
      @filters << Flapjack::Filters::Ok.new(options)
      @filters << Flapjack::Filters::ScheduledMaintenance.new(options)
      @filters << Flapjack::Filters::UnscheduledMaintenance.new(options)
      @filters << Flapjack::Filters::DetectMassClientFailures.new(options)
      @filters << Flapjack::Filters::Delays.new(options)
      @filters << Flapjack::Filters::Acknowledgement.new(options)

      @boot_time    = Time.now
      @fqdn         = `/bin/hostname -f`.chomp
      @pid          = Process.pid
      @instance_id  = "#{@fqdn}:#{@pid}"

      # FIXME: all of the below keys assume there is only ever one executive running;
      # we could generate a fuid and save it to disk, and prepend it from that
      # point on...

      # TODO unset on exit?
      @redis.set('boot_time', @boot_time.to_i)

      # FIXME: add an administrative function to reset all event counters
      if @redis.hget('event_counters', 'all').nil?
        @redis.hset('event_counters', 'all', 0)
        @redis.hset('event_counters', 'ok', 0)
        @redis.hset('event_counters', 'failure', 0)
        @redis.hset('event_counters', 'action', 0)
      end

      @redis.zadd('executive_instances', @boot_time.to_i, @instance_id)
      @redis.hset("event_counters:#{@instance_id}", 'all', 0)
      @redis.hset("event_counters:#{@instance_id}", 'ok', 0)
      @redis.hset("event_counters:#{@instance_id}", 'failure', 0)
      @redis.hset("event_counters:#{@instance_id}", 'action', 0)
    end

    def start
      @logger.info("Booting main loop.")

      until @should_quit
        @logger.debug("Waiting for event...")
        event = Flapjack::Data::Event.next(:redis => @redis)
        process_event(event) unless event.nil?
      end

      @logger.info("Exiting main loop.")
    end

    # this must use a separate connection to the main Executive one, as it's running
    # from a different fiber while the main one is blocking.
    def stop
      @should_quit = true
      @redis.rpush('events', JSON.generate('type'    => 'shutdown',
                                           'host'    => '',
                                           'service' => '',
                                           'state'   => ''))
    end

  private

    def process_event(event)
      pending = Flapjack::Data::Event.pending_count(:redis => @redis)
      @logger.debug("#{pending} events waiting on the queue")
      @logger.debug("Raw event received: #{event.inspect}")
      time_at = event.time
      time_at_str = time_at ? ", #{Time.at(time_at).to_s}" : ''
      @logger.debug("Processing Event: #{event.id}, #{event.type}, #{event.state}, #{event.summary}#{time_at_str}")

      entity_check = ('shutdown' == event.type) ? nil :
                       Flapjack::Data::EntityCheck.for_event_id(event.id, :redis => @redis)

      result = update_keys(event, entity_check)
      return if result[:shutdown]

      blocker = nil

      if result[:skip_filters]
        @logger.debug("Not generating notifications for event #{event.id} because filtering was skipped")
        return
      else
        blocker = @filters.find {|filter| filter.block?(event) }
      end

      if blocker
        @logger.debug("Not generating notifications for event #{event.id} because this filter blocked: #{blocker.name}")
        return
      end

      @logger.info("Generating notifications for event #{event.id}, #{event.type}, #{event.state}, #{event.summary}#{time_at_str}")
      generate_notification_messages(event, entity_check)
    end

    def update_keys(event, entity_check)
      result    = { :skip_filters => false }
      timestamp = Time.now.to_i
      @event_count = @redis.hincrby('event_counters', 'all', 1)
      @redis.hincrby("event_counters:#{@instance_id}", 'all', 1)

      # FIXME skip if entity_check.nil?

      # FIXME: validate that the event is sane before we ever get here
      # FIXME: create an event if there is dodgy data

      case event.type
      # Service events represent changes in state on monitored systems
      when 'service'
        # Track when we last saw an event for a particular entity:check pair
        entity_check.last_update = timestamp

        if event.ok?
          @redis.hincrby('event_counters', 'ok', 1)
          @redis.hincrby("event_counters:#{@instance_id}", 'ok', 1)
        elsif event.failure?
          @redis.hincrby('event_counters', 'failure', 1)
          @redis.hincrby("event_counters:#{@instance_id}", 'failure', 1)
          @redis.hset('unacknowledged_failures', @event_count, event.id)
        end

        event.previous_state = entity_check.state
        event.previous_state_duration = Time.now.to_i - entity_check.last_change.to_i
        @logger.info("No previous state for event #{event.id}") if event.previous_state.nil?

        # If there is a state change, update record with: the time, the new state
        if event.state != event.previous_state
          entity_check.update_state(event.state, :timestamp => timestamp,
            :summary => event.summary, :client => event.client,
            :count => @event_count)
        end

        # No state change, and event is ok, so no need to run through filters
        # OR
        # If the service event's state is ok and there was no previous state, don't alert.
        # This stops new checks from alerting as "recovery" after they have been added.
        if !event.previous_state && event.ok?
          @logger.debug("setting skip_filters to true because there was no previous state and event is ok")
          result[:skip_filters] = true
        end

        entity_check.update_current_scheduled_maintenance

      # Action events represent human or automated interaction with Flapjack
      when 'action'
        # When an action event is processed, store the event.
        @redis.hset(event.id + ':actions', timestamp, event.state)
        @redis.hincrby('event_counters', 'action', 1)
        @redis.hincrby("event_counters:#{@instance_id}", 'action', 1)

        if event.acknowledgement? && event.acknowledgement_id
          @redis.hdel('unacknowledged_failures', event.acknowledgement_id)
        end
      when 'shutdown'
        # should this be logged as an action instead? being minimally invasive for now
        result[:shutdown] = true
      end

      result
    end

    # takes an event for which a notification needs to be generated, works out the type of
    # notification, updates the notification history in redis, generates the notifications
    def generate_notification_messages(event, entity_check)
      timestamp = Time.now.to_i
      notification_type = 'unknown'
      case event.type
      when 'service'
        case event.state
        when 'ok'
          notification_type = 'recovery'
        when 'warning', 'critical', 'unknown'
          notification_type = 'problem'
        end
      when 'action'
        case event.state
        when 'acknowledgement'
          notification_type = 'acknowledgement'
        when 'test_notifications'
          notification_type = 'test'
        end
      end
      @redis.set("#{event.id}:last_#{notification_type}_notification", timestamp)
      @redis.set("#{event.id}:last_#{event.state}_notification", timestamp) if event.failure?
      @redis.rpush("#{event.id}:#{notification_type}_notifications", timestamp)
      @redis.rpush("#{event.id}:#{event.state}_notifications", timestamp) if event.failure?
      @logger.debug("Notification of type #{notification_type} is being generated for #{event.id}.")

      contacts = entity_check.contacts

      if contacts.empty?
        @notifylog.info("#{Time.now.to_s} | #{event.id} | #{notification_type} | NO CONTACTS")
        return
      end

      notification = Flapjack::Data::Notification.for_event(event, :type => notification_type)

      enqueue_messages( apply_notification_rules( notification.messages(:contacts => contacts) ) )

    end

    # time restrictions match?
    # nil rule.time_restrictions matches
    # times (start, end) within time restrictions will have any UTC offset removed and will be
    # considered to be in the timezone of the contact
    def rule_occurring_now?(rule, opts)
      contact = opts[:contact]
      return true if rule.time_restrictions.nil? or rule.time_restrictions.empty?

      timezone = contact.timezone(:default => @default_contact_timezone)
      Time.zone = timezone.identifier
      usertime = Time.zone.now

      match = rule.time_restrictions.any? do |tr|

        # add contact's timezone to the time restriction hash
        # TODO: move back to Data::NotificationRule ?

        tr = symbolize(tr)
        if tr[:start_date].is_a?(String)
          tr[:start_date] = { :time => tr[:start_date] }
        end
        if tr[:start_date].is_a?(Hash)
          tr[:start_date][:time] = Time.zone.parse(tr[:start_date][:time])
          tr[:start_date][:zone] = timezone.identifier
        end

        if tr[:end_time].is_a?(String)
          tr[:end_time] = { :time => tr[:end_time] }
        end
        if tr[:end_time].is_a?(Hash)
          tr[:end_time][:time] = Time.zone.parse(tr[:end_time][:time])
          tr[:end_time][:zone] = timezone.identifier
        end

        puts "\nusertime: #{usertime}, timezone: #{timezone}"
        puts "tr hash: #{tr.inspect}"
        schedule = IceCube::Schedule.from_hash(tr)
        puts "schedule: #{schedule} - #{schedule.to_yaml}"
        puts schedule.first(3)
        occurring = schedule.occurring_at?(usertime)
        puts "occurring? #{occurring}"
        occurring
      end
      !!match
    end

    # delete messages based on entity name(s), tags, severity, time of day
    def apply_notification_rules(messages)
      # first get all rules matching entity and time
      @logger.debug "apply_notification_rules: got messages with size #{messages.size}"

      # don't consider notification rules if the contact has none

      tuple = messages.map do |message|
        @logger.debug "considering message: #{message.medium} #{message.notification.event.id} #{message.notification.event.state}"
        @logger.debug "contact_id: #{message.contact.id}"
        rules    = message.contact.notification_rules
        @logger.debug "found #{rules.length} rules for this message's contact"
        event_id = message.notification.event.id
        options  = {}
        options[:no_rules_for_contact] = true if rules.empty?
        # filter based on entity, tags, severity, time of day
        matchers = rules.find_all do |rule|
          rule.match_entity?(event_id) && rule_occurring_now?(rule, :contact => message.contact)
        end
        [message, matchers, options]
      end

      # matchers are rules of the contact that have matched the current event
      # for time and entity

      @logger.debug "apply_notification_rules: num messages after entity and time matching: #{tuple.size}"

      # delete the matcher for all entities if there are more specific matchers
      tuple = tuple.map do |message, matchers, options|
        if matchers.length > 1
          have_specific = matchers.detect do |matcher|
            matcher.entities or matcher.entity_tags
          end
          if have_specific
            # delete the rule for all entities
            matchers.map! do |matcher|
              matcher.entities.nil? and matcher.entity_tags.nil? ? nil : matcher
            end
          end
        end
        [message, matchers, options]
      end

      # delete media based on blackholes
      tuple = tuple.find_all do |message, matchers, options|
        severity = message.notification.event.state
        # or use message.notification.contents['state']
        matchers.none? {|matcher| matcher.blackhole?(severity) }
      end

      @logger.debug "apply_notification_rules: num messages after removing blackhole matches: #{tuple.size}"

      # delete any media that doesn't meet severity<->media constraints
      tuple = tuple.find_all do |message, matchers, options|
        severity = message.notification.event.state
        options[:no_rules_for_contact] ||
          matchers.any? {|matcher|
            matcher.media_for_severity(severity).include?(message.medium) ||
              (@logger.warn("got nil for matcher.media_for_severity(#{severity}), matcher: #{matcher.inspect}") && false)
          }
      end

      @logger.debug "apply_notification_rules: num messages after severity-media constraints: #{tuple.size}"

      # delete media based on notification interval
      tuple = tuple.find_all do |message, matchers, options|
        not message.contact.drop_notifications?(:media => message.medium,
                                                :check => message.notification.event.id,
                                                :state => message.notification.event.state)
      end

      @logger.debug "apply_notification_rules: num messages after pruning for notification intervals: #{tuple.size}"

      tuple.map do |message, matchers, options|
        message
      end
    end

    def enqueue_messages(messages)

      messages.each do |message|
        media_type = message.medium
        contents   = message.contents
        event_id   = message.notification.event.id

        @notifylog.info("#{Time.now.to_s} | #{event_id} | " +
          "#{message.notification.type} | #{message.contact.id} | #{media_type} | #{message.address}")

        unless @queues[media_type.to_sym]
          @logger.error("no queue for media type: #{media_type}")
          return
        end

        @logger.info("Enqueueing #{media_type} alert for #{event_id} to #{message.address}")

        message.contact.update_sent_alert_keys(:media => message.medium,
                                               :check => message.notification.event.id,
                                               :state => message.notification.event.state)
          # drop_alerts_for_contact:#{self.id}:#{media}:#{check}:#{state}

        # TODO consider changing Resque jobs to use raw blpop like the others
        case media_type.to_sym
        when :sms
          Resque.enqueue_to(@queues[:sms], Flapjack::Gateways::SmsMessagenet, contents)
        when :email
          Resque.enqueue_to(@queues[:email], Flapjack::Gateways::Email, contents)
        when :jabber
          # TODO move next line up into other notif value setting above?
          contents['event_count'] = @event_count if @event_count
          @redis.rpush(@queues[:jabber], Yajl::Encoder.encode(contents))
        when :pagerduty
          @redis.rpush(@queues[:pagerduty], Yajl::Encoder.encode(contents))
        end
      end

   end

  end
end
