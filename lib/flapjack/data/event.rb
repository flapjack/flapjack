#!/usr/bin/env ruby

require 'oj'

module Flapjack
  module Data
    class Event

      attr_accessor :counter, :previous_state, :previous_state_duration

      attr_reader :check, :summary, :details, :acknowledgement_id

      # creates, or modifies, an event object and adds it to the events list in redis
      #   'type'      => 'service',
      #   'state'     => state,
      #   'summary'   => check_output,
      #   'time'      => timestamp
      def self.push(queue, event, opts = {})
        raise "Redis connection not set" unless redis = opts[:redis]

        event['time'] = Time.now.to_i if event['time'].nil?

        begin
          event_json = ::Oj.dump(event)
        rescue Oj::Error => e
          if opts[:logger]
            opts[:logger].warn("Error serialising event json: #{e}, event: #{event.inspect}")
          end
          event_json = nil
        end

        if event_json
          redis.multi do
            redis.lpush(queue, event_json)
            redis.lpush("#{queue}_actions", "+")
          end
        end
      end

      def self.foreach_on_queue(queue, opts = {})
        raise "Redis connection not set" unless redis = opts[:redis]

        parse_json_proc = Proc.new {|event_json|
          begin
            ::Oj.load( event_json )
          rescue Oj::Error => e
            if opts[:logger]
              opts[:logger].warn("Error deserialising event json: #{e}, raw json: #{event_json.inspect}")
            end
            nil
          end
        }

        if opts[:archive_events]
          dest = "events_archive:#{Time.now.utc.strftime "%Y%m%d%H"}"
          while event_json = redis.rpoplpush(queue, dest)
            redis.expire(dest, opts[:events_archive_maxage])
            event = parse_json_proc.call(event_json)
            yield self.new(event) if block_given? && event
          end
        else
          while event_json = redis.rpop(queue)
            event = parse_json_proc.call(event_json)
            yield self.new(event) if block_given? && event
          end
        end
      end

      def self.wait_for_queue(queue, opts = {})
        raise "Redis connection not set" unless redis = opts[:redis]
        redis.brpop("#{queue}_actions")
      end

      # Provide a count of the number of events on the queue to be processed.
      def self.pending_count(queue, opts = {})
        raise "Redis connection not set" unless redis = opts[:redis]

        redis.llen(queue)
      end

      def self.create_acknowledgement(queue, entity_name, check, opts = {})
        data = { 'type'               => 'action',
                 'state'              => 'acknowledgement',
                 'entity'             => entity_name,
                 'check'              => check,
                 'summary'            => opts[:summary],
                 'duration'           => opts[:duration],
                 'acknowledgement_id' => opts[:acknowledgement_id]
               }
        self.push(queue, data, :redis => opts[:redis])
      end

      def self.test_notifications(queue, entity_name, check, opts = {})
        data = { 'type'               => 'action',
                 'state'              => 'test_notifications',
                 'entity'             => entity_name,
                 'check'              => check,
                 'summary'            => opts[:summary],
                 'details'            => opts[:details]
               }
        self.push(queue, data, :redis => opts[:redis])
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

