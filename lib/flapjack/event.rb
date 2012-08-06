#!/usr/bin/env ruby

require 'redis'
require 'json'

module Flapjack
  class Event
    # Helper method for getting the next event.
    #
    # Has a blocking a non-blocking method signature.
    #
    # Calling next with :block => true, we wait indefinitely for events coming
    # from other systems. This is the default behaviour.
    #
    # Calling next with :block => false, will return a nil if there are no
    # events on the queue.
    #
    def self.next(opts={})
      defaults = { :block => true }
      options  = defaults.merge(opts)
      block    = options[:block]

      # In production, we wait indefinitely for events coming from other systems.
      if block
        raw   = Flapjack.persistence.blpop('events').last
        event = ::JSON.parse(raw)
        self.new(event)
      # In testing, we care if there are no events on the queue.
      else
        raw    = Flapjack.persistence.lpop('events')
        result = nil

        if raw
          event = ::JSON.parse(raw)
          result = self.new(event)
        end

        return result
      end
    end

    # Provide a count of the number of events on the queue to be processed.
    def self.pending_count
      Flapjack.persistence.llen('events')
    end

    def initialize(attrs={})
      @attrs = attrs
    end

    def state
      @attrs['state'].downcase
    end

    def ok?
      (state == 'ok') or (state == 'up')
    end

    def unknown?
      state == 'unknown'
    end

    def unreachable?
      state == 'unreachable'
    end

    def warning?
      state == 'warning'
    end

    def critical?
      state == 'critical'
    end

    def failure?
      warning? or critical?
    end

    def entity
      @attrs['entity'] ? e = @attrs['entity'].downcase : e = nil
    end

    def check
      @attrs['check']
    end

    def id
      entity ? e = entity : e = '-'
      check  ? c = check  : c = '-'
      e + ':' + c
    end

    # FIXME: site specific
    def client
      c = entity ? entity.split('-').first : nil
    end

    def type
      @attrs['type'].downcase
    end

    def summary
      @attrs['summary']
    end

    def when
      Time.at(@attrs['when'])
    end

    def action?
      type == 'action'
    end

    def service?
      type == 'service'
    end

    def acknowledgement?
      action? and state == 'acknowledgement'
    end
  end
end

