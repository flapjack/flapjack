#!/usr/bin/env ruby

require 'yajl/json_gem'

module Flapjack
  module Data
    class Event

      attr_accessor :previous_state, :previous_state_duration

      attr_reader :check, :summary, :details, :acknowledgement_id

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

        defaults = { :block => true,
                     :archive_events => false,
                     :events_archive_maxage => (3 * 60 * 60) }
        options  = defaults.merge(opts)

        if options[:archive_events]
          dest = "events_archive:#{Time.now.utc.strftime "%Y%m%d%H"}"
          if options[:block]
            raw = redis.brpoplpush('events', dest, 0)
          else
            raw = redis.rpoplpush('events', dest)
            return unless raw
          end
          redis.expire(dest, options[:events_archive_maxage])
        else
          if options[:block]
            raw = redis.brpop('events', 0)[1]
          else
            raw = redis.rpop('events')
            return unless raw
          end
        end
        begin
          parsed = ::JSON.parse( raw )
        rescue => e
          if options[:logger]
            options[:logger].warn("Error deserialising event json: #{e}, raw json: #{raw.inspect}")
          end
          return nil
        end
        self.new( parsed )
      end

      # creates, or modifies, an event object and adds it to the events list in redis
      #   'type'      => 'service',
      #   'state'     => state,
      #   'summary'   => check_output,
      #   'time'      => timestamp
      def self.add(evt, opts = {})
        raise "Redis connection not set" unless redis = opts[:redis]

        evt['time'] = Time.now.to_i if evt['time'].nil?
        redis.rpush('events', ::Yajl::Encoder.encode(evt))
      end

      # Provide a count of the number of events on the queue to be processed.
      def self.pending_count(opts = {})
        raise "Redis connection not set" unless redis = opts[:redis]

        redis.llen('events')
      end

      def self.create_acknowledgement(entity_name, check, opts = {})
        data = { 'type'               => 'action',
                 'state'              => 'acknowledgement',
                 'entity'             => entity_name,
                 'check'              => check,
                 'summary'            => opts[:summary],
                 'duration'           => opts[:duration],
                 'acknowledgement_id' => opts[:acknowledgement_id]
               }
        add(data, :redis => opts[:redis])
      end

      def self.test_notifications(entity_name, check, opts = {})
        data = { 'type'               => 'action',
                 'state'              => 'test_notifications',
                 'entity'             => entity_name,
                 'check'              => check,
                 'summary'            => opts[:summary],
                 'details'            => opts[:details]
               }
        add(data, :redis => opts[:redis])
      end

      def initialize(attrs = {})
        ['type', 'state', 'entity', 'check', 'time', 'summary', 'details',
         'acknowledgement_id', 'duration'].each do |key|
          instance_variable_set("@#{key}", attrs[key])
        end
      end

      def state
        return unless @state
        @state.downcase
      end

      def entity
        return unless @entity
        @entity.downcase
      end

      def duration
        return unless @duration
        @duration.to_i
      end

      def time
        return unless @time
        @time.to_i
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
        return unless @type
        @type.downcase
      end

      def service?
        type == 'service'
      end

      def acknowledgement?
        (type == 'action') && (state == 'acknowledgement')
      end

      def test_notifications?
        (type == 'action') && (state == 'test_notifications')
      end

      def ok?
        (state == 'ok') || (state == 'up')
      end

      def failure?
        ['critical', 'warning', 'unknown'].include?(state)
      end

      # # Not used anywhere
      # def unreachable?
      #   state == 'unreachable'
      # end
    end
  end
end

