#!/usr/bin/env ruby

require 'oj'
require 'flapjack/data/tag_set'

module Flapjack
  module Data
    class Event

      attr_accessor :counter, :id_hash, :tags

      attr_reader :check, :summary, :details, :acknowledgement_id

      REQUIRED_KEYS = ['type', 'state', 'entity', 'check', 'summary']
      OPTIONAL_KEYS = ['time', 'details', 'acknowledgement_id', 'duration', 'tags']

      VALIDATIONS = {
        proc {|e| e['type'].is_a?(String) &&
          ['service', 'action'].include?(e['type'].downcase) } =>
          "type must be either 'service' or 'action'",

        proc {|e| e['state'].is_a?(String) &&
            ['ok', 'warning', 'critical', 'unknown', 'acknowledgement',
             'test_notifications'].include?(e['state'].downcase) } =>
          "state must be one of 'ok', 'warning', 'critical', 'unknown', " +
          "'acknowledgement' or 'test_notifications'",

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

        proc {|e| e['tags'].nil? ||
                  (e['tags'].is_a?(Array) &&
                   e['tags'].all? {|tag| tag.is_a?(String)}) } =>
          "tags must be an array of strings",
      }

      # Helper method for getting the next event.
      #
      # Has a blocking and non-blocking method signature.
      #
      # Calling next with :block => true, we wait indefinitely for events coming
      # from other systems. This is the default behaviour.
      #
      # Calling next with :block => false, will return a nil if there are no
      # events on the queue.
      def self.next(queue, opts = {})
        raise "Redis connection not set" unless redis = opts[:redis]

        defaults = { :block => true,
                     :archive_events => false,
                     :events_archive_maxage => (3 * 60 * 60) }
        options  = defaults.merge(opts)

        archive_dest = nil
        base_time_str = Time.now.utc.strftime("%Y%m%d%H")

        if options[:archive_events]
          archive_dest = "events_archive:#{base_time_str}"
          if options[:block]
            raw = redis.brpoplpush(queue, archive_dest, 0)
          else
            raw = redis.rpoplpush(queue, archive_dest)
            return unless raw
          end
        else
          if options[:block]
            raw = redis.brpop(queue, 0)[1]
          else
            raw = redis.rpop(queue)
            return unless raw
          end
        end
        parsed = parse_and_validate(raw, :logger => options[:logger])
        if parsed.nil?
          # either bad json or invalid data -- in either case we'll
          # store the raw data in a rejected list
          rejected_dest = "events_rejected:#{base_time_str}"
          if options[:archive_events]
            redis.multi
            redis.lrem(archive_dest, 1, raw)
            redis.lpush(rejected_dest, raw)
            redis.exec
            redis.expire(archive_dest, options[:events_archive_maxage])
          else
            redis.lpush(rejected_dest, raw)
          end
          return
        elsif options[:archive_events]
          redis.expire(archive_dest, options[:events_archive_maxage])
        end
        self.new(parsed)
      end

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
          opts[:logger].error("Invalid event data received, #{error_str} #{parsed.inspect}")
        end
        nil
      rescue Oj::Error => e
        if opts[:logger]
          opts[:logger].error("Error deserialising event json: #{e}, raw json: #{raw.inspect}")
        end
        nil
      end

      # creates, or modifies, an event object and adds it to the events list in redis
      #   'entity'    => entity,
      #   'check'     => check,
      #   'type'      => 'service',
      #   'state'     => state,
      #   'summary'   => check_output,
      #   'details'   => check_long_output,
      #   'time'      => timestamp
      def self.add(evt, opts = {})
        raise "Redis connection not set" unless redis = opts[:redis]

        evt['time'] = Time.now.to_i if evt['time'].nil?
        redis.lpush('events', ::Oj.dump(evt))
      end

      # Provide a count of the number of events on the queue to be processed.
      def self.pending_count(queue, opts = {})
        raise "Redis connection not set" unless redis = opts[:redis]

        redis.llen(queue)
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
        # details is optional. set it to nil if it only contains whitespace
        @details = (@details.is_a?(String) && ! @details.strip.empty?) ? @details.strip : nil
        if attrs['tags']
          @tags = Flapjack::Data::TagSet.new
          attrs['tags'].each {|tag| @tags.add(tag)}
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
