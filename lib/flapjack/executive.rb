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
require 'flapjack/data/entity_check'
require 'flapjack/data/event'
require 'flapjack/notification/common'
require 'flapjack/notification/sms'
require 'flapjack/notification/email'
require 'flapjack/pikelet'

module Flapjack

  class Executive
    include Flapjack::Pikelet

    def initialize(opts = {})
      bootstrap(opts)

      @redis = opts[:redis]

      @queues = {:email  =>  opts['email_queue'] || 'email_notifications',
                 :sms    =>    opts['sms_queue'] || 'sms_notifications',
                 :jabber => opts['jabber_queue'] || 'jabber_notifications'}

      @notifylog = Log4r::Logger.new("executive")
      @notifylog.add(Log4r::FileOutputter.new("notifylog", :filename => "log/notify.log"))

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
      # FIXME: assumes there is only ever one executive running
      @redis.set('boot_time', @boot_time.to_i)
      # FIXME: resets counters on every bootup. probably not a good idea. probably.
      # FIXME: add an administrative function to reset all event counters
      @redis.hset('event_counters', 'all', 0)
      @redis.hset('event_counters', 'ok', 0)
      @redis.hset('event_counters', 'failure', 0)
      @redis.hset('event_counters', 'action', 0)
    end

    def update_keys(event)
      result    = { :skip_filters => false }
      timestamp = Time.now.to_i
      @redis.hincrby('event_counters', 'all', 1)

      case event.type
      # Service events represent changes in state on monitored systems
      when 'service'
        # Track when we last saw an event for a particular entity:check pair
        @redis.hset("check:" + event.id, 'last_update', timestamp)

        @redis.hincrby('event_counters', 'ok', 1)      if (event.ok?)
        @redis.hincrby('event_counters', 'failure', 1) if (event.failure?)

        old_state = @redis.hget("check:" + event.id, 'state')

        case
        # If there is a state change, update record with: the time, the new state
        when event.state != old_state
          # FIXME: validate that the event is sane before we ever get here
          # FIXME: create an event if there is dodgy data

          # Note the current state (for speedy lookups)
          @redis.hset("check:" + event.id, 'state',       event.state)
          # FIXME: rename to last_state_change?
          @redis.hset("check:" + event.id, 'last_change', timestamp)

          # Retain all state changes for entity:check pair
          @redis.rpush("#{event.id}:states", timestamp)
          @redis.set("#{event.id}:#{timestamp}:state",   event.state)
          @redis.set("#{event.id}:#{timestamp}:summary", event.summary)

          # If the service event's state is ok and there was no previous state, don't alert.
          # This stops new checks from alerting as "recovery" after they have been added.
          result[:skip_filters] = true unless old_state

          case event.state
          when 'warning', 'critical', 'down'
            @redis.zadd('failed_checks', timestamp, event.id)
            # FIXME: Iterate through a list of tags associated with an entity:check pair, and update counters
            @redis.zadd('failed_checks:client:' + event.client, timestamp, event.id) if event.client
          else
            @redis.zrem('failed_checks', event.id)
            # FIXME: Iterate through a list of tags associated with an entity:check pair, and update counters
            @redis.zrem('failed_checks:client:' + event.client, event.id) if event.client
          end
        # No state change, and event is ok, so no need to run through filters
        when event.ok?
          result[:skip_filters] = true
        end

        entity_check = Flapjack::Data::EntityCheck.for_event_id(event.id, :redis => @redis)
        entity_check.update_scheduled_maintenance

      # Action events represent human or automated interaction with Flapjack
      when 'action'
        # When an action event is processed, store the event.
        @redis.hset(event.id + ':actions', timestamp, event.state)
        @redis.hincrby('event_counters', 'action', 1) if (event.ok?)
      when 'shutdown'
        # should this be logged as an action instead? being minimally invasive for now
        result[:shutdown] = true
      end

      result
    end

    # takes an event for which a notification needs to be generated, works out the type of
    # notification, updates the notification history in redis, calls other methods to work out who
    # to notify, by what method, and finally to have the notifications sent
    def generate_notification(event)
      timestamp = Time.now.to_i
      notification_type = 'unknown'
      case event.type
      when 'service'
        case event.state
        when 'ok', 'up', 'unknown'
          notification_type = 'recovery'
        when 'warning', 'critical', 'down'
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

      send_notifications(event, notification_type, contacts_for_check(event.id))
    end

    # takes a check, looks up contacts that are interested in this check (or in the check's entity)
    # and returns an array of contact ids
    # eg
    #   contacts_for_check("clientx:checky") -> [ '2', '534' ]
    #
    def contacts_for_check(check)
      entity = check.split(':').first
      entity_id = @redis.get("entity_id:#{entity}")
      if entity_id
        check = entity_id.to_s + ":" + check.split(':').last
        @logger.debug("contacts for #{entity_id} (#{entity}): " + @redis.smembers("contacts_for:#{entity_id}").length.to_s)
        @logger.debug("contacts for #{check}: " + @redis.smembers("contacts_for:#{check}").length.to_s)
        union = @redis.sunion("contacts_for:#{entity_id}", "contacts_for:#{check}")
        @logger.debug("contacts for union of #{entity_id} and #{check}: " + union.length.to_s)
        union
      else
        @logger.debug("entity [#{entity}] has no contacts")
        []
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

    # puts a notification into the jabber queue (redis list)
    def submit_jabber(notification)
      @redis.rpush(@queues[:jabber], Yajl::Encoder.encode(notification))
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
          @logger.debug("send_notifications: sending notification: #{notif.inspect}")

          case media_type
          when "sms"
            Resque.enqueue_to(@queues[:sms], Notification::Sms, notif)
          when "email"
            Resque.enqueue_to(@queues[:email], Notification::Email, notif)
          when "jabber"
            submit_jabber(notif)
          end
        }
        if media.length == 0
          @notifylog.info("#{Time.now.to_s} | #{event.id} | #{notification_type} | #{contact} | NO MEDIA FOR CONTACT")
        end
      }
      if contacts.length == 0
        @notifylog.info("#{Time.now.to_s} | #{event.id} | #{notification_type} | NO CONTACTS")
      end
    end

    def process_event(event)
      @logger.debug("#{Flapjack::Data::Event.pending_count(:persistence => @redis)} events waiting on the queue")
      @logger.debug("Raw event received: #{event.inspect}")
      @logger.info("Processing Event: #{event.id}, #{event.type}, #{event.state}, #{event.summary}, #{Time.at(event.time).to_s}")

      result       = update_keys(event)
      return if result[:shutdown]
      skip_filters = result[:skip_filters]

      blocker = @filters.find {|filter| filter.block?(event) } unless skip_filters

      if not blocker and not skip_filters
        @logger.info("#{Time.now}: Sending notifications for event #{event.id}")
        generate_notification(event)
      elsif blocker
        blocker_names = [ blocker.name ]
        @logger.info("#{Time.now}: Not sending notifications for event #{event.id} because these filters blocked: #{blocker_names.join(', ')}")
      else
        @logger.info("#{Time.now}: Not sending notifications for event #{event.id} because state is ok with no change, or no prior state")
      end
    end

    def add_shutdown_event
      event = {'type'    => 'shutdown',
               'host'    => '',
               'service' => '',
               'state'   => ''}
      @redis.rpush('events', Yajl::Encoder.encode(event))
    end

    def main
      @logger.info("Booting main loop.")
      until @should_stop
        @logger.info("Waiting for event...")
        event = Flapjack::Data::Event.next(:persistence => @redis)
        process_event(event) unless event.nil?
      end
      @redis.quit
      @logger.info("Exiting main loop.")
    end
  end
end
