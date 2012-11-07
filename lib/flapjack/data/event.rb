#!/usr/bin/env ruby

module Flapjack
  module Data
    class Event

      attr_accessor :previous_state

      # Helper method for getting the next event.
      #
      # Has a blocking and non-blocking method signature.
      #
      # Calling next with :block => true, we wait indefinitely for events coming
      # from other systems. This is the default behaviour.
      #
      # Calling next with :block => false, will return a nil if there are no
      # events on the queue.
      #
      def self.next(opts={})
        raise "Redis connection not set" unless redis = opts[:redis]

        defaults = { :block => true }
        options  = defaults.merge(opts)

        # In production, we wait indefinitely for events coming from other systems.
        if options[:block]
          return self.new( ::JSON.parse( redis.blpop('events', 0).last ) )
        end

        # In testing, we take care that there are no events on the queue.
        return unless raw = redis.lpop('events')
        self.new( ::JSON.parse(raw) )
      end

      # creates, or modifies, an event object and adds it to the events list in redis
      #   'type'      => 'service',
      #   'state'     => state,
      #   'summary'   => check_output,
      #   'time'      => timestamp
      def self.add(evt, opts = {})
        raise "Redis connection not set" unless redis = opts[:redis]

        evt['time'] = Time.now.to_i if evt['time'].nil?
        redis.rpush('events', Yajl::Encoder.encode(evt))
      end

      # Provide a count of the number of events on the queue to be processed.
      def self.pending_count(opts = {})
        raise "Redis connection not set" unless redis = opts[:redis]

        redis.llen('events')
      end

      def initialize(attrs={})
        @attrs = attrs
        @attrs['time'] = Time.now.to_i unless @attrs.has_key?('time')
      end

      def state
        return unless @attrs['state']
        @attrs['state'].downcase
      end

      def entity
        return unless @attrs['entity']
        @attrs['entity'].downcase
      end

      def check
        @attrs['check']
      end


      # FIXME some values are only set for certain event types --
      # this may not be the best way to do this
      def acknowledgement_id
        @attrs['acknowledgement_id']
      end

      def duration
        return unless @attrs['duration']
        @attrs['duration'].to_i
      end
      # end FIXME


      def id
        (entity || '-') + ':' + (check || '-')
      end

      # FIXME: site specific
      def client
        return unless entity
        entity.split('-').first
      end

      def type
        return unless @attrs['type']
        @attrs['type'].downcase
      end

      def summary
        @attrs['summary']
      end

      def time
        return unless @attrs['time']
        @attrs['time'].to_i
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

    end
  end
end

