#!/usr/bin/env ruby

require 'log4r/outputter/fileoutputter'

require 'flapjack'
require 'flapjack/filters/acknowledgement'
require 'flapjack/filters/ok'
require 'flapjack/filters/scheduled_maintenance'
require 'flapjack/filters/unscheduled_maintenance'
require 'flapjack/filters/detect_mass_client_failures'
require 'flapjack/filters/delays'
require 'flapjack/notification/common'
require 'flapjack/notification/sms'
require 'flapjack/notification/email'
require 'flapjack/event'
require 'flapjack/pikelet'

module Flapjack

  class Executive
    include Flapjack::Pikelet

    def initialize(opts = {})
      bootstrap(opts.merge(:redis => {:driver => 'synchrony'}))
      
      @notifylog = Log4r::Logger.new("executive")
      @notifylog.add(Log4r::FileOutputter.new("notifylog", :filename => "log/notify.log"))

      # FIXME: Put loading filters into separate method
      options = { :log => @logger, :persistence => @persistence }
      @filters = []
      @filters << Flapjack::Filters::Ok.new(options)
      @filters << Flapjack::Filters::ScheduledMaintenance.new(options)
      @filters << Flapjack::Filters::UnscheduledMaintenance.new(options)
      @filters << Flapjack::Filters::DetectMassClientFailures.new(options)
      @filters << Flapjack::Filters::Delays.new(options)
      @filters << Flapjack::Filters::Acknowledgement.new(options)

      @boot_time = Time.now
      # FIXME: assumes there is only ever one executive running
      @persistence.set('boot_time', @boot_time.to_i)
      # FIXME: resets counters on every bootup. probably not a good idea. probably.
      # FIXME: add an administrative function to reset all event counters
      @persistence.hset('event_counters', 'all', 0)
      @persistence.hset('event_counters', 'ok', 0)
      @persistence.hset('event_counters', 'failure', 0)
      @persistence.hset('event_counters', 'action', 0)
    end

    def update_keys(event)
      result    = { :skip_filters => false }
      timestamp = Time.now.to_i
      @persistence.hincrby('event_counters', 'all', 1)

      case event.type
      # Service events represent changes in state on monitored systems
      when 'service'
        # Track when we last saw an event for a particular entity:check pair
        @persistence.hset(event.id, 'last_update', timestamp)

        @persistence.hincrby('event_counters', 'ok', 1)      if (event.ok?)
        @persistence.hincrby('event_counters', 'failure', 1) if (event.failure?)

        old_state = @persistence.hget(event.id, 'state')

        case
        # If there is a state change, update record with: the time, the new state
        when event.state != old_state
          # FIXME: validate that the event is sane before we ever get here
          # FIXME: create an event if there is dodgy data

          # Note the current state (for speedy lookups)
          @persistence.hset(event.id, 'state',       event.state)
          # FIXME: rename to last_state_change?
          @persistence.hset(event.id, 'last_change', timestamp)

          # Retain all state changes for entity:check pair
          @persistence.rpush("#{event.id}:states", timestamp)
          @persistence.set("#{event.id}:#{timestamp}:state",   event.state)
          @persistence.set("#{event.id}:#{timestamp}:summary", event.summary)

          # If the service event's state is ok and there was no previous state, don't alert.
          # This stops new checks from alerting as "recovery" after they have been added.
          result[:skip_filters] = true unless old_state

          case event.state
          when 'warning', 'critical', 'down'
            @persistence.zadd('failed_checks', timestamp, event.id)
            # FIXME: Iterate through a list of tags associated with an entity:check pair, and update counters
            @persistence.zadd('failed_checks:client:' + event.client, timestamp, event.id) if event.client
          else
            @persistence.zrem('failed_checks', event.id)
            # FIXME: Iterate through a list of tags associated with an entity:check pair, and update counters
            @persistence.zrem('failed_checks:client:' + event.client, event.id) if event.client
          end
        # No state change, and event is ok, so no need to run through filters
        when event.ok?
          result[:skip_filters] = true
        end

      # Action events represent human or automated interaction with Flapjack
      when 'action'
        # When an action event is processed, store the event.
        @persistence.hset(event.id + ':actions', timestamp, event.state)
        @persistence.hincrby('event_counters', 'action', 1) if (event.ok?)
      when 'shutdown'
        # should this be logged as an action instead? being minimally invasive for now
        result[:shutdown] = true
      end

      return result
    end

    # Process any events we have until there's none left
    def drain_events
      loop do
        event = Event.next(:block => false, :persistence => @persistence)
        break unless event
        process_event(event)
      end
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
      @persistence.set("#{event.id}:last_#{notification_type}_notification", timestamp)
      @persistence.rpush("#{event.id}:#{notification_type}_notifications", timestamp)
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
      entity_id = @persistence.get("entity_id:#{entity}")
      if entity_id
        check = entity_id.to_s + ":" + check.split(':').last
        @logger.debug("contacts for #{entity_id} (#{entity}): " + @persistence.smembers("contacts_for:#{entity_id}").length.to_s)
        @logger.debug("contacts for #{check}: " + @persistence.smembers("contacts_for:#{check}").length.to_s)
        union = @persistence.sunion("contacts_for:#{entity_id}", "contacts_for:#{check}")
        @logger.debug("contacts for union of #{entity_id} and #{check}: " + union.length.to_s)
        return union
      else
        @logger.debug("entity [#{entity}] has no contacts")
        return []
      end
    end

    # takes a contact ID and returns a hash containing each of the media the contact wishes to be
    # contacted by, and the associated address for each.
    # eg:
    #   media_for_contact('123') -> { :sms => "+61401234567", :email => "gno@free.dom" }
    #
    def media_for_contact(contact)
      return @persistence.hgetall("contact_media:#{contact}")
    end

    # generates a fairly unique identifier to use as a message id
    def fuid
      fuid = self.object_id.to_i.to_s + '-' + Time.now.to_i.to_s + '.' + Time.now.tv_usec.to_s
    end

    # puts a notification into the jabber queue (redis list)
    def submit_jabber(notification)
      @persistence.rpush('jabber_notifications', Yajl::Encoder.encode(notification))
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
                         'contact_first_name' => @persistence.hget("contact:#{contact_id}", 'first_name'),
                         'contact_last_name'  => @persistence.hget("contact:#{contact_id}", 'last_name'), }

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
            Resque.enqueue_to('sms_notifications', Notification::Sms, notif)
          when "email"
            Resque.enqueue_to('email_notifications', Notification::Email, notif)
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
      @logger.debug("#{Event.pending_count(:persistence => @persistence)} events waiting on the queue")
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
      @persistence.rpush('events', Yajl::Encoder.encode(event))      
    end

    def main
      @logger.info("Booting main loop.")
      until @should_stop
        @logger.info("Waiting for event...")
        @logger.info(@persistence.inspect)
        event = Event.next(:persistence => @persistence)
        process_event(event) unless event.nil?
      end
      @persistence.disconnect
      @logger.info("Exiting main loop.")
    end
  end
end
