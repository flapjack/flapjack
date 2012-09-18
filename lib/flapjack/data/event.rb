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
        defaults = { :block => true }
        options  = defaults.merge(opts)
        block    = options[:block]

        # In production, we wait indefinitely for events coming from other systems.
        if block
          raw   = opts[:persistence].blpop('events').last
          event = ::JSON.parse(raw)
          self.new(event)
        else
          # In testing, we take care that there are no events on the queue.
          raw    = opts[:persistence].lpop('events')
          result = nil

          if raw
            event  = ::JSON.parse(raw)
            result = self.new(event)
          end

          result
        end
      end

      # Provide a count of the number of events on the queue to be processed.
      def self.pending_count(opts = {})
        opts[:persistence].llen('events')
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

      def acknowledgement_id
        @attrs['acknowledgement_id']
      end

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

