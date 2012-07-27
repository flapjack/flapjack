#!/usr/bin/env ruby

require 'log4r'
require 'log4r/outputter/syslogoutputter'
require 'flapjack/patches'
require 'flapjack/filters/acknowledgement'
require 'flapjack/filters/ok'
require 'flapjack/filters/scheduled_maintenance'
require 'flapjack/filters/unscheduled_maintenance'
require 'flapjack/filters/detect_mass_client_failures'
require 'flapjack/filters/delays'
require 'flapjack/event'
require 'flapjack/events'
require 'redis'

module Flapjack
  class Executive
    # Boots flapjack executive
    def self.run(options={})
      self.new(options)
    end

    attr_accessor :log

    def initialize(options={})
      @options     = options
      @persistence = ::Redis.new
      @events      = Flapjack::Events.new

      @log = Log4r::Logger.new("executive")
      @log.add(Log4r::StdoutOutputter.new("executive"))
      @log.add(Log4r::SyslogOutputter.new("executive"))

      @notifylog = Log4r::Logger.new("executive")
      @notifylog.add(Log4r::FileOutputter.new("notifylog", {:filename => "log/notify.log"}))

      options = { :log => @log, :persistence => @persistence }
      @filters = []
      @filters << Flapjack::Filters::Ok.new(options)
      @filters << Flapjack::Filters::ScheduledMaintenance.new(options)
      @filters << Flapjack::Filters::UnscheduledMaintenance.new(options)
      @filters << Flapjack::Filters::DetectMassClientFailures.new(options)
      @filters << Flapjack::Filters::Delays.new(options)
      @filters << Flapjack::Filters::Acknowledgement.new(options)

      @boot_time = Time.now
      @persistence.set('boot_time', @boot_time.to_i)
      @persistence.hset('event_counters', 'all', 0)
      @persistence.hset('event_counters', 'ok', 0)
      @persistence.hset('event_counters', 'failure', 0)
      @persistence.hset('event_counters', 'action', 0)
    end

    def update_keys(event)
      result = { :skip_filters => false }
      timestamp = Time.now.to_i
      @persistence.hincrby('event_counters', 'all', 1)
      case event.type
      when 'service'
        # FIXME: this is added for development, perhaps it can be removed in production,
        # depends if we want to display 'last check time' or have logic depend on this
        @persistence.hset(event.id, 'last_update', timestamp)

        @persistence.hincrby('event_counters', 'ok', 1)      if (event.ok?)
        @persistence.hincrby('event_counters', 'failure', 1) if (event.failure?)

        # When an service event is processed, we check to see if new state matches the old state.
        # If the state is different, update the database with: the time, the new state
        old_state = @persistence.hget(event.id, 'state')
        if event.state != old_state

          # current state only (for speedy lookup)
          @persistence.hset(event.id, 'state',       event.state)
          @persistence.hset(event.id, 'last_change', timestamp)

          # retention of all state changes
          @persistence.rpush("#{event.id}:states", timestamp)
          @persistence.set("#{event.id}:#{timestamp}:state",   event.state)
          @persistence.set("#{event.id}:#{timestamp}:summary", event.summary)

          case event.state
          when 'warning', 'critical'
            @persistence.zadd('failed_checks', timestamp, event.id)
            @persistence.zadd('failed_checks:client:' + event.client, timestamp, event.id)
          else
            @persistence.zrem('failed_checks', event.id)
            @persistence.zrem('failed_checks:client:' + event.client, event.id)
          end
        elsif event.ok?
          # no state change, and ok, so SKIP FILTERS
          result = { :skip_filters => true }
        end

      when 'action'
        # When an action event is processed, store the event.
        @persistence.hset(event.id + ':actions', timestamp, event.state)
        @persistence.hincrby('event_counters', 'action', 1) if (event.ok?)
      end

      return result
    end

    # process any events we have until there's none left
    def process_events

      loop do
        event = @events.gimmie
        break unless event
        process_result(event)
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
        when 'ok', 'unknown'
          notification_type = 'recovery'
        when 'warning', 'critical'
          notification_type = 'problem'
        end
      when 'action'
        case event.state
        when 'acknowledgement'
          notification_type = 'problem'
        end
      end
      @persistence.set("#{event.id}:last_#{notification_type}_notification", timestamp)
      @persistence.rpush("#{event.id}:#{notification_type}_notifications", timestamp)
      @log.debug("Notification of type #{notification_type} is being generated for #{event.id}.")

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
        check = entity_id + ":" + check.split(':').last
        @log.debug("contacts for #{entity_id} (#{entity}): " + @persistence.smembers("contacts_for:#{entity_id}").length.to_s)
        @log.debug("contacts for #{check}: " + @persistence.smembers("contacts_for:#{check}").length.to_s)
        union = @persistence.sunion("contacts_for:#{entity_id}", "contacts_for:#{check}")
        @log.debug("contacts for union of #{entity_id} and #{check}: " + union.length.to_s)
        return union
      else
        @log.debug("entity [#{entity}] has no contacts")
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

    # takes an event, a notification type, and an array of contacts and creates jobs in rescue
    # (eventually) for each notification
    #
    def send_notifications(event, notification_type, contacts)
      contacts.each {|contact_id|
        media = media_for_contact(contact_id)
        media.each_pair {|media, address|
          @notifylog.info("#{Time.now.to_s} | #{event.id} | #{notification_type} | #{contact_id} | #{media} | #{address}")
          # queue this notification
          # FIXME: make a Contact class perhaps
          notification = { :event_id           => event.id,
                           :state              => event.state,
                           :summary            => event.summary,
                           :notification_type  => notification_type,
                           :contact_id         => contact_id,
                           :contact_first_name => @persistence.hget("contact:#{contact_id}", 'first_name'),
                           :contact_last_name  => @persistence.hget("contact:#{contact_id}", 'last_name'),
                           :media              => media,
                           :address            => address }
          case media
          when "sms"
            Resque.enqueue(Flapjack::Notification::Sms, notification)
          when "email"
            Resque.enqueue(Flapjack::Notification::Email, notification)
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

    def process_result(event)

      @log.debug("#{@events.size} events waiting on the queue")
      @log.debug("Processing Event: #{event.id}, #{event.type}, #{event.state}, #{event.summary}")

      #@log.info("Storing event.")
      #@persistence.save(event)

      skip_filters = update_keys(event)[:skip_filters]
      #blockers = []
      unless skip_filters
        # changing this to run all filters rather than stopping at the first failure
        # i think we'll need to be more subtle here, provide a mechanism for a filter to say 'stop
        # processing now' otherwise keep processing filters even after a block. ... maybe not.
        #blockers = @filters.find_all {|filter| filter.block?(event) }
        # and trying reverting to how it was originally where first blocking filter stops filter
        # processing
        blocker = @filters.find {|filter| filter.block?(event) }
      end
      #if blockers.length == 0 and not skip_filters
      if not blocker and not skip_filters
        $notification = "#{Time.now}: Sending notifications for event #{event.id}"
        @log.info($notification)
        generate_notification(event)
      elsif blocker
        #blocker_names = blockers.collect{|blocker| blocker.name }
        blocker_names = [ blocker.name ]
        $notification = "#{Time.now}: Not sending notifications for event #{event.id} because these filters blocked: #{blocker_names.join(', ')}"
        @log.info($notification)
      else
        $notification = "#{Time.now}: Not sending notifications for event #{event.id} because state is ok with no change"
      end
    end

    def main
      @log.info("Booting main loop.")
      loop do
        @log.info("Waiting for event...")
        event = @events.next
        process_result(event)
      end
    end
  end
end
