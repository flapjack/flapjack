#!/usr/bin/env ruby

require 'log4r'
require 'log4r/outputter/syslogoutputter'
require 'flapjack/patches'
require 'flapjack/filters/acknowledgement_of_failed'
require 'flapjack/filters/ok'
require 'flapjack/filters/acknowledged'
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
      @filters << Flapjack::Filters::AcknowledgementOfFailed.new(options)
      @filters << Flapjack::Filters::Ok.new(options)
      @filters << Flapjack::Filters::Acknowledged.new(options)
    end

    def update_keys(event)
      timestamp = Time.now.to_i
      case event.type
      when 'service'
        # When an service event is processed, we check to see if new state matches the old state.
        # If the state is different, update the database with: the time, the new state
        old_state = @persistence.hget(event.id, 'state')
        if event.state != old_state
          @persistence.hset(event.id, 'state', event.state)
          @persistence.hset(event.id, 'last_change', timestamp)
          case event.state
          when 'warning', 'critical'
            @persistence.zadd('failed_services', timestamp, event.id)
          else
            @persistence.zrem('failed_services', event.id)
          end

        end

      when 'action'
        # When an action event is processed, store the event.
        @persistence.hset('action_for;#{event.id}', timestamp, event.state)
      end

    end

    def process_result
      @log.info("Waiting for event...")
      event = @events.next

      @log.debug("#{@events.size} events waiting on the queue")

      #@log.info("Storing event.")
      #@persistence.save(event)

      update_keys(event)

      block = @filters.find {|filter| filter.block?(event) }
      if not block
        @log.info("Sending notifications for event #{event.host};#{event.service}")
      else
        @log.info("Not sending notifications for event #{event.host};#{event.service} because the #{block.name} filter blocked")
      end
    end

    def main
      @log.info("Booting main loop.")
      loop do
        process_result
      end
    end
  end
end
