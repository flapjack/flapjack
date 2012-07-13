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
  class Notifier
    # Boots the notifier.
    def self.run(options={})
      self.new(options)
    end

    attr_accessor :log

    def initialize(options={})
      @options     = options
      @persistence = ::Redis.new
      @events      = Flapjack::Events.new

      @log = Log4r::Logger.new("notifier")
      @log.add(Log4r::StdoutOutputter.new("notifier"))
      @log.add(Log4r::SyslogOutputter.new("notifier"))


      options = { :log => @log, :persistence => @persistence }
      @filters = []
      @filters << Flapjack::Filters::Ok.new(options)
      @filters << Flapjack::Filters::ScheduledMaintenance.new(options)
      @filters << Flapjack::Filters::UnscheduledMaintenance.new(options)
      @filters << Flapjack::Filters::DetectMassClientFailures.new(options)
      @filters << Flapjack::Filters::Delays.new(options)
      @filters << Flapjack::Filters::Acknowledgement.new(options)
    end

    def update_keys(event)
      result = { :skip_filters => false }
      timestamp = Time.now.to_i
      case event.type
      when 'service'
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
            @persistence.zadd('failed_services', timestamp, event.id)
            @persistence.zadd('failed_services:client:' + event.client, timestamp, event.id)
          else
            @persistence.zrem('failed_services', event.id)
            @persistence.zrem('failed_services:client:' + event.client, event.id)
          end
        elsif event.ok?
          # no state change, and ok, so SKIP FILTERS
          result = { :skip_filters => true }
        end

      when 'action'
        # When an action event is processed, store the event.
        @persistence.hset(event.id + ':actions', timestamp, event.state)
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

    def send_notification(event)
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
      @log.debug("Notification of type #{notification_type} has been sent for #{event.id}. (LIES)")
    end

    def process_result(event)

      @log.debug("#{@events.size} events waiting on the queue")
      @log.debug("Processing Event: #{event.id}, #{event.type}, #{event.state}, #{event.summary}")

      #@log.info("Storing event.")
      #@persistence.save(event)

      skip_filters = update_keys(event)[:skip_filters]
      blockers = []
      unless skip_filters
        # changing this to run all filters rather than stopping at the first failure
        # i think we'll need to be more subtle here, provide a mechanism for a filter to say 'stop
        # processing now' otherwise keep processing filters even after a block. ... maybe not.
        blockers = @filters.find_all {|filter| filter.block?(event) }
      end
      if blockers.length == 0 and not skip_filters
        $notification = "#{Time.now}: Sending notifications for event #{event.id}"
        @log.info($notification)
        send_notification(event)
      else
        blocker_names = blockers.collect{|blocker| blocker.name }
        $notification = "#{Time.now}: Not sending notifications for event #{event.id} because these filters blocked: #{blocker_names.join(', ')}"
        @log.info($notification)
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
