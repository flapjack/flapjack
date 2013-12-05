#!/usr/bin/env ruby

require 'oj'

module Flapjack
  module Data
    class Event

      attr_accessor :counter

      attr_reader :check_name, :summary, :details, :acknowledgement_id

      # creates, or modifies, an event object and adds it to the events list in redis
      #   'entity'    => entity_name,
      #   'check'     => check_name,
      #   'type'      => 'service',
      #   'state'     => state,
      #   'summary'   => check_output,
      #   'details'   => check_long_output,
      #   'time'      => timestamp
      def self.push(queue, event, opts = {})
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
          Flapjack.redis.multi do
            Flapjack.redis.lpush(queue, event_json)
            Flapjack.redis.lpush("#{queue}_actions", "+")
          end
        end
      end

      # Provide a count of the number of events on the queue to be processed.
      def self.pending_count(queue)
        Flapjack.redis.llen(queue)
      end

      def self.create_acknowledgement(queue, entity_name, check_name, opts = {})
        data = { 'type'               => 'action',
                 'state'              => 'acknowledgement',
                 'entity'             => entity_name,
                 'check'              => check_name,
                 'summary'            => opts[:summary],
                 'duration'           => opts[:duration],
                 'acknowledgement_id' => opts[:acknowledgement_id]
               }
        self.push(queue, data, opts)
      end

      def self.test_notifications(queue, entity_name, check_name, opts = {})
        data = { 'type'               => 'action',
                 'state'              => 'test_notifications',
                 'entity'             => entity_name,
                 'check'              => check_name,
                 'summary'            => opts[:summary],
                 'details'            => opts[:details]
               }
        self.push(queue, data, opts)
      end

      def initialize(attrs = {})
        [:type, :state, :entity, :check, :time, :summary,
         :details, :acknowledgement_id, :duration].each do |key|
          case key
          when :entity
            @entity_name = attrs['entity']
          when :check
            @check_name = attrs['check']
          else
            instance_variable_set("@#{key.to_s}", attrs[key.to_s])
          end
        end
        # details is optional. set it to nil if it only contains whitespace
        @details = (@details.is_a?(String) && ! @details.strip.empty?) ? @details.strip : nil
      end

      def state
        return unless @state
        @state.downcase
      end

      def entity_name
        return unless @entity_name
        @entity_name.downcase
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
        (entity_name || '-') + ':' + (check_name || '-')
      end

      def type
        return unless @type
        @type.downcase
      end

      def notification_type
        case type
        when 'service'
          case state
          when 'ok'
            'recovery'
          when 'warning', 'critical', 'unknown'
            'problem'
          end
        when 'action'
          case state
          when 'acknowledgement'
            'acknowledgement'
          when 'test_notifications'
            'test'
          end
        else
          'unknown'
        end
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
    end
  end
end

