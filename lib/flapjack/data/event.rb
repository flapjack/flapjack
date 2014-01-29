#!/usr/bin/env ruby

require 'oj'
require 'flapjack/redis_proxy'

module Flapjack
  module Data
    class Event

      attr_accessor :counter

      attr_reader :check_name, :summary, :details, :acknowledgement_id

      REQUIRED_KEYS = ['type', 'state', 'entity', 'check', 'summary']
      OPTIONAL_KEYS = ['time', 'details', 'acknowledgement_id', 'duration']

      VALIDATIONS = {
        proc {|e| ['service', 'action'].include?(e['type']) } =>
          "type must be either 'service' or 'action'",

        proc {|e| ['ok', 'warning', 'critical', 'unknown', 'acknowledgement', 'test_notifications'].include?(e['state']) } =>
          "state must be one of 'ok', 'warning', 'critical', 'unknown', 'acknowledgement' or 'test_notifications'",

        proc {|e| e['entity'].is_a?(String) } =>
          "entity must be a string",

        proc {|e| e['check'].is_a?(String) } =>
          "check must be a string",

        proc {|e| e['summary'].is_a?(String) } =>
          "summary must be a string",

        proc {|e| e['time'].nil? ||
                  e['time'].is_a?(Integer) ||
                 (e['time'].is_a?(String) && !!(e['time'] =~ /^\d+$/)) } =>
          "time must be a positive integer, or a string castable to one",

        proc {|e| e['details'].nil? || e['details'].is_a?(String) } =>
          "details must be a string",

        proc {|e| e['acknowledgement_id'].nil? ||
                  e['acknowledgement_id'].is_a?(String) ||
                  e['acknowledgement_id'].is_a?(Integer) } =>
          "acknowledgement_id must be a string or an integer",

        proc {|e| e['duration'].nil? ||
                  e['duration'].is_a?(Integer) ||
                 (e['duration'].is_a?(String) && !!(e['duration'] =~ /^\d+$/)) } =>
          "duration must be a positive integer, or a string castable to one",
      }

      def self.parse_and_validate(raw, opts = {})
        errors = []
        if parsed = ::Oj.load(raw)

          if parsed.is_a?(Hash)
            missing_keys = REQUIRED_KEYS.select {|k|
              !parsed.has_key?(k) || parsed[k].nil? || parsed[k].empty?
            }
            unless missing_keys.empty?
              errors << "Event hash has missing keys '#{missing_keys.join('\', \'')}'"
            end

            unknown_keys =  parsed.keys - (REQUIRED_KEYS + OPTIONAL_KEYS)
            unless unknown_keys.empty?
              errors << "Event hash has unknown key(s) '#{unknown_keys.join('\', \'')}'"
            end
          else
            errors << "Event must be a JSON hash, see https://github.com/flpjck/flapjack/wiki/DATA_STRUCTURES#event-queue"
          end

          if errors.empty?
            errors += VALIDATIONS.keys.inject([]) {|ret,vk|
              ret << "Event #{VALIDATIONS[vk]}" unless vk.call(parsed)
              ret
            }
          end

          return parsed if errors.empty?
        end

        if opts[:logger]
          error_str = errors.nil? ? '' : errors.join(', ')
          opts[:logger].error("Invalid event data received #{error_str}#{parsed.inspect}")
        end
        nil
      rescue Oj::Error => e
        if opts[:logger]
          opts[:logger].error("Error deserialising event json: #{e}, raw json: #{raw.inspect}")
        end
        nil
      end

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

