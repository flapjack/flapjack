#!/usr/bin/env ruby

require 'log4r'
require 'log4r/outputter/fileoutputter'

require 'flapjack'
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
require 'flapjack/notification/sms'
require 'flapjack/notification/email'
require 'flapjack/pikelet'
require 'flapjack/redis_pool'

module Flapjack

  class Executive
    include Flapjack::GenericPikelet

    alias_method :generic_bootstrap, :bootstrap
    alias_method :generic_cleanup,   :cleanup

    def bootstrap(opts = {})
      generic_bootstrap(opts)

      @redis = Flapjack::RedisPool.new(:config => opts[:redis_config], :size => 1)

      @queues = {:email     => @config['email_queue'],
                 :sms       => @config['sms_queue'],
                 :jabber    => @config['jabber_queue'],
                 :pagerduty => @config['pagerduty_queue']}

      notifylog  = @config['notification_log_file'] || 'log/notify.log'
      @notifylog = Log4r::Logger.new("executive")
      @notifylog.add(Log4r::FileOutputter.new("notifylog", :filename => notifylog))

      # FIXME: Put loading filters into separate method
      # FIXME: should we make the filters more configurable by the end user?
      options = { :log => @logger, :persistence => @redis }
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

    def cleanup
      @redis.empty! if @redis
      generic_cleanup
    end

    def main
      @logger.info("Booting main loop.")

      until should_quit?
        @logger.info("Waiting for event...")
        event = Flapjack::Data::Event.next(:persistence => @redis)
        process_event(event) unless event.nil?
      end

      @logger.info("Exiting main loop.")
    end

    # this must use a separate connection to the main Executive one, as it's running
    # from a different fiber while the main one is blocking.
    def add_shutdown_event(opts = {})
      return unless redis = opts[:redis]
      redis.rpush('events', JSON.generate('type'    => 'shutdown',
                                          'host'    => '',
                                          'service' => '',
                                          'state'   => ''))
    end

  private

    def process_event(event)
      @logger.debug("#{Flapjack::Data::Event.pending_count(:persistence => @redis)} events waiting on the queue")
      @logger.debug("Raw event received: #{event.inspect}")
      time_at = event.time
      time_at_str = time_at ? ", #{Time.at(time_at).to_s}" : ''
      @logger.info("Processing Event: #{event.id}, #{event.type}, #{event.state}, #{event.summary}#{time_at_str}")

      entity_check = (event.type == 'shutdown') ? nil :
                       Flapjack::Data::EntityCheck.for_event_id(event.id, :redis => @redis)

      result       = update_keys(event, entity_check)
      return if result[:shutdown]
      skip_filters = result[:skip_filters]

      blocker = @filters.find {|filter| filter.block?(event) } unless skip_filters

      if skip_filters
        @logger.info("#{Time.now}: Not sending notifications for event #{event.id} because filtering was skipped")
        return
      end

      if blocker
        blocker_names = [ blocker.name ]
        @logger.info("#{Time.now}: Not sending notifications for event #{event.id} because these filters blocked: #{blocker_names.join(', ')}")
        return
      end

      @logger.info("#{Time.now}: Sending notifications for event #{event.id}")
      send_notification_messages(event, entity_check)
    end

    def update_keys(event, entity_check)
      result    = { :skip_filters => false }
      timestamp = Time.now.to_i
      @event_count = @redis.hincrby('event_counters', 'all', 1)
      @event_count = @redis.hincrby("event_counters:#{@instance_id}", 'all', 1)

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
    # notification, updates the notification history in redis, sends the notifications
    def send_notification_messages(event, entity_check)
      timestamp = Time.now.to_i
      notification_type = 'unknown'
      case event.type
      when 'service'
        case event.state
        when 'ok', 'unknown'
          notification_type = 'recovery'
        when 'warning', 'critical'
          notification_type = 'problem'
        end
      when 'action'
        case event.state
        when 'acknowledgement'
          notification_type = 'acknowledgement'
        end
      end
      @redis.set("#{event.id}:last_#{notification_type}_notification", timestamp)
      @redis.rpush("#{event.id}:#{notification_type}_notifications", timestamp)
      @logger.debug("Notification of type #{notification_type} is being generated for #{event.id}.")

      contacts = entity_check.contacts

      if contacts.empty?
        @notifylog.info("#{Time.now.to_s} | #{event.id} | #{notification_type} | NO CONTACTS")
        return
       end

      notification = Flapjack::Data::Notification.for_event(event, :type => notification_type)

      notification.messages(:contacts => contacts).each do |msg|
        media_type = msg.medium.to_sym

        @notifylog.info("#{Time.now.to_s} | #{event.id} | " +
          "#{notification_type} | #{msg.contact.id} | #{media_type.to_s} | #{msg.address}")

        unless @queues[media_type]
          # TODO log error
          next
        end

        contents = msg.contents

        # TODO consider changing Resque jobs to use raw blpop like the others
        case media_type
        when :sms
          Resque.enqueue_to(@queues[:sms], Notification::Sms, contents)
        when :email
          Resque.enqueue_to(@queues[:email], Notification::Email, contents)
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
