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
require 'flapjack/data/event'
require 'flapjack/notification/common'
require 'flapjack/notification/sms'
require 'flapjack/notification/email'
require 'flapjack/pikelet'

module Flapjack

  class Executive
    include Flapjack::Pikelet

    def setup
      @redis = build_redis_connection_pool
      redis_client_status = @redis.client
      @logger.debug("Flapjack::Executive.initialize: @redis client status: " + redis_client_status.inspect)

      @queues = {:email     => @config['email_queue'],
                 :sms       => @config['sms_queue'],
                 :jabber    => @config['jabber_queue'],
                 :pagerduty => @config['pagerduty_queue']}

      notifylog  = @config['notification_log_file'] || 'log/notify.log'
      @notifylog = Log4r::Logger.new("executive")
      @notifylog.add(Log4r::FileOutputter.new("notifylog", :filename => notifylog))

      # FIXME: Put loading filters into separate method
      options = { :log => @logger, :persistence => @redis }
      @filters = []
      @filters << Flapjack::Filters::Ok.new(options)
      @filters << Flapjack::Filters::ScheduledMaintenance.new(options)
      @filters << Flapjack::Filters::UnscheduledMaintenance.new(options)
      @filters << Flapjack::Filters::DetectMassClientFailures.new(options)
      @filters << Flapjack::Filters::Delays.new(options)
      @filters << Flapjack::Filters::Acknowledgement.new(options)

      @boot_time = Time.now

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
    end

    def main
      setup

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
      generate_notification(event, entity_check)
    end

    def update_keys(event, entity_check)
      result    = { :skip_filters => false }
      timestamp = Time.now.to_i
      @event_count = @redis.hincrby('event_counters', 'all', 1)

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
        elsif event.failure?
          @redis.hincrby('event_counters', 'failure', 1)
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

        entity_check.update_scheduled_maintenance

      # Action events represent human or automated interaction with Flapjack
      when 'action'
        # When an action event is processed, store the event.
        @redis.hset(event.id + ':actions', timestamp, event.state)
        @redis.hincrby('event_counters', 'action', 1) if event.ok?

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
    # notification, updates the notification history in redis, calls other methods to work out who
    # to notify, by what method, and finally to have the notifications sent
    def generate_notification(event, entity_check)
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

      send_notifications(event, notification_type,
                         Flapjack::Data::Contact.find_all_for_entity_check(entity_check, :redis => @redis))
    end

    # takes an event, a notification type, and an array of contacts and creates jobs in resque
    # (eventually) for each notification
    def send_notifications(event, notification_type, contacts)
      notification = { 'event_id'          => event.id,
                       'state'             => event.state,
                       'summary'           => event.summary,
                       'time'              => event.time,
                       'notification_type' => notification_type }

      contacts.each {|contact_id|
        media = media_for_contact(contact_id)

        contact_deets = {'contact_id'         => contact_id,
                         'contact_first_name' => @redis.hget("contact:#{contact_id}", 'first_name'),
                         'contact_last_name'  => @redis.hget("contact:#{contact_id}", 'last_name'), }

        notification = notification.merge(contact_deets)

        media.each_pair {|media_type, address|

          @notifylog.info("#{Time.now.to_s} | #{event.id} | #{notification_type} | #{contact_id} | #{media} | #{address}")
          # queue this notification
          # FIXME: make a Contact class perhaps
          notif = notification.dup
          notif['media']   = media_type
          notif['address'] = address
          notif['id']      = fuid
          dur = event.duration
          notif['duration'] = dur if dur
          @logger.debug("send_notifications: sending notification: #{notif.inspect}")

          case media_type
          when "sms"
            if @queues[:sms]
              Resque.enqueue_to(@queues[:sms], Notification::Sms, notif)
            end
          when "email"
            if @queues[:email]
              Resque.enqueue_to(@queues[:email], Notification::Email, notif)
            end
          when "jabber"
            if @queues[:jabber]
              notif['event_count'] = @event_count if @event_count
              # puts a notification into the jabber queue (redis list)
              @redis.rpush(@queues[:jabber], Yajl::Encoder.encode(notif))
            end
          when "pagerduty"
            if @queues[:pagerduty]
              @redis.rpush(@queues[:pagerduty], Yajl::Encoder.encode(notif))
            end
          end
        }
        if media.length == 0
          @notifylog.info("#{Time.now.to_s} | #{event.id} | #{notification_type} | #{contact_id} | NO MEDIA FOR CONTACT")
        end
      }
      if contacts.length == 0
        @notifylog.info("#{Time.now.to_s} | #{event.id} | #{notification_type} | NO CONTACTS")
      end
    end

    # takes a contact ID and returns a hash containing each of the media the contact wishes to be
    # contacted by, and the associated address for each.
    # eg:
    #   media_for_contact('123') -> { :sms => "+61401234567", :email => "gno@free.dom" }
    #
    def media_for_contact(contact)
      @redis.hgetall("contact_media:#{contact}")
    end

    # generates a fairly unique identifier to use as a message id
    def fuid
      fuid = self.object_id.to_i.to_s + '-' + Time.now.to_i.to_s + '.' + Time.now.tv_usec.to_s
    end

  end
end
