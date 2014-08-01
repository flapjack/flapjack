#!/usr/bin/env ruby

require 'oj'

require 'flapjack/patches'

require 'flapjack/data/contact'
require 'flapjack/data/event'
require 'flapjack/data/entity'

# TODO might want to split the class methods out to a separate class, DAO pattern
# ( http://en.wikipedia.org/wiki/Data_access_object ).

module Flapjack

  module Data

    class EntityCheck

      STATE_OK              = 'ok'
      STATE_WARNING         = 'warning'
      STATE_CRITICAL        = 'critical'
      STATE_UNKNOWN         = 'unknown'

      NOTIFICATION_STATES = [:problem, :warning, :critical, :unknown,
                             :recovery, :acknowledgement]

      attr_accessor :entity, :check

      def self.for_event_id(event_id, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        entity_name, check_name = event_id.split(':', 2)
        create_entity = options[:create_entity]
        logger = options[:logger]
        entity = Flapjack::Data::Entity.find_by_name(entity_name,
          :create => create_entity, :logger => logger, :redis => redis)
        self.new(entity, check_name, :logger => logger, :redis => redis)
      end

      def self.for_entity_name(entity_name, check_name, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        create_entity = options[:create_entity]
        logger = options[:logger]
        entity = Flapjack::Data::Entity.find_by_name(entity_name,
          :create => create_entity, :logger => logger, :redis => redis)
        self.new(entity, check_name, :logger => logger, :redis => redis)
      end

      def self.for_entity_id(entity_id, check, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        create_entity = options[:create_entity]
        logger = options[:logger]
        entity = Flapjack::Data::Entity.find_by_id(entity_id,
          :create => create_entity, :logger => logger, :redis => redis)
        self.new(entity, check, :redis => redis)
      end

      def self.for_entity(entity, check, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        logger = options[:logger]
        self.new(entity, check, :logger => logger, :redis => redis)
      end

      def self.find_all_for_entity_name(entity_name, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        redis.zrange("current_checks:#{entity_name}", 0, -1)
      end

      def self.find_all(options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        self.conflate_to_keys(self.find_all_by_entity(:redis => redis))
      end

      def self.find_all_by_entity(options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        d = {}
        redis.zrange("current_entities", 0, -1).each {|entity|
          d[entity] = redis.zrange("current_checks:#{entity}", 0, -1)
        }
        d
      end

      def self.count_all(options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        redis.zrange("current_entities", 0, -1).inject(0) {|memo, entity|
          memo + redis.zcount("current_checks:#{entity}", '-inf', '+inf')
        }
      end

      def self.find_all_failing(options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        self.conflate_to_keys(self.find_all_failing_by_entity(:redis => redis))
      end

      def self.find_all_failing_by_entity(options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        redis.zrange("failed_checks", 0, -1).inject({}) do |memo, key|
          entity, check = key.split(':', 2)
          if !!redis.zscore("current_checks:#{entity}", check)
            memo[entity] ||= []
            memo[entity] << check
          end
          memo
        end
      end

      def self.count_all_failing(options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        redis.zrange("failed_checks", 0, -1).count do |key|
          entity, check = key.split(':', 2)
          !!redis.zscore("current_checks:#{entity}", check)
        end
      end

      def self.unacknowledged_failing(options = {})
        raise "Redis connection not set" unless redis = options[:redis]

        redis.zrange('failed_checks', '0', '-1').reject {|entity_check|
          redis.exists(entity_check + ':unscheduled_maintenance')
        }.collect {|entity_check|
          Flapjack::Data::EntityCheck.for_event_id(entity_check, :redis => redis)
        }
      end

      def self.conflate_to_keys(entity_checks_hash)
        result = []
        entity_checks_hash.each {|entity, checks|
          checks.each {|check|
            result << "#{entity}:#{check}"
          }
        }
        result
      end

      def self.find_maintenance(options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        d = []
        type = options[:type]
        keys = redis.keys('*scheduled_maintenances')
        keys.each do |k|
          entity = k.split(':')[0]
          check = k.split(':')[1]
          ec = Flapjack::Data::EntityCheck.for_entity_name(entity, check, :redis => redis)
          # Only return entries where the state matches the one passed in
          next unless options[:state] == ec.state
          windows = ec.maintenances(nil, nil, type.to_sym => true)
          windows.each do |window|
            entry = { :name => "#{entity}:#{check}",
                      :state => ec.state
            }
            # Only return entries where the summary matches the reason passed in, or the reason isn't set
            next unless options[:reason].nil? || options[:reason].match(window[:summary])
            # Only return entries where the maintenance start and end times are in the bounds of the input
            d.push(entry.merge!(window)) if check_timestamp(options['started'], window[:start_time]) && check_timestamp(options['finishing'], window[:end_time]) && check_interval(options['duration'], window[:duration])
          end
        end
        d
      end

      def self.delete_maintenance(options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        entries = find_maintenance(options)
        success = true
        entries.each do |entry|
          puts "Entry can't be deleted as it finished in the past: #{entry}"; success = false if entry[:end_time] < Time.now.to_i
          if success
            name = entry[:name]
            entity = name.split(':')[0]
            check = name.split(':')[1]

            ec = Flapjack::Data::EntityCheck.for_entity_name(entity, check, :redis => redis)
            success = ec.end_scheduled_maintenance(entry[:start_time]) if options[:type] == 'scheduled'
            success = ec.end_unscheduled_maintenance(entry[:end_time]) if options[:type] == 'unscheduled'

            puts "The following entry failed to delete: #{entry}" unless success
          end
        end
        success
      end


      def self.check_interval(input, maintenance_duration)
        # If no duration was specified, give back all results
        return true unless input
        # FIXME: Require chronic_duration in the proper place
        require 'chronic_duration'

        ctime = input
        # ChronicDuration can't parse timestamps for strings starting with before or after.
        # Strip the before or after for the conversion only, but use it for the comparison later
        ['more than', 'less than'].each { |prefix| ctime = input.gsub(prefix, '') if input.start_with?(prefix) }
        input_duration = ChronicDuration.parse(ctime, :keep_zero => true)

        abort("Failed to parse time: #{input}") if input_duration.nil?

        return maintenance_duration < input_duration if input.start_with?('less than')
        return maintenance_duration > input_duration if input.start_with?('more than')
        maintenance_duration == input_duration
      end

      def self.check_timestamp(input, maintenance_timestamp)
        # If no time was specified, give back all results
        return true unless input

        ctime = input
        # Chronic can't parse timestamps for strings starting with before or after.
        # Strip the before or after for the conversion only, but use it for the comparison later
        %w(before after).each { |prefix| ctime = input.gsub(prefix, '') if input.start_with?(prefix) }

        # We assume timestamps are rooted against the current time.
        # Chronic doesn't always handle this correctly, so we need to handhold it a little
        input_timestamp = Chronic.parse(ctime, :keep_zero => true).to_i
        input_timestamp = Chronic.parse(ctime + ' from now', :keep_zero => true).to_i if input_timestamp == 0

        abort("Failed to parse time: #{input}") if input_timestamp == 0

        return (input.end_with?('ago') ? maintenance_timestamp > input_timestamp : maintenance_timestamp < input_timestamp) if input.start_with?('less than')
        return (input.end_with?('ago') ? maintenance_timestamp < input_timestamp : maintenance_timestamp > input_timestamp) if input.start_with?('more than')
        return maintenance_timestamp < input_timestamp if input.start_with?('before')
        return maintenance_timestamp > input_timestamp if input.start_with?('after')
        # FIXME: How should we handle equality here?
        maintenance_timestamp == input_timestamp if input.start_with?('on')
      end

      def self.in_unscheduled_maintenance_for_event_id?(event_id, options)
        raise "Redis connection not set" unless redis = options[:redis]
        redis.exists("#{event_id}:unscheduled_maintenance")
      end

      def self.in_scheduled_maintenance_for_event_id?(event_id, options)
        raise "Redis connection not set" unless redis = options[:redis]
        redis.exists("#{event_id}:scheduled_maintenance")
      end

      def self.state_for_event_id?(event_id, options)
        raise "Redis connection not set" unless redis = options[:redis]
        redis.hget("check:#{event_id}", 'state')
      end

      # takes an array of ages (in seconds) to split all checks up by
      # - age means how long since the last update
      # - 0 age is implied if not explicitly passed
      # returns arrays of all current checks hashed by age range upper bound, eg:
      #
      # EntityCheck.find_all_split_by_freshness([60, 300], opts) =>
      #   {   0 => [ 'foo-app-01:SSH' ],
      #      60 => [ 'foo-app-01:Ping', 'foo-app-01:Disk / Utilisation' ],
      #     300 => [] }
      #
      # you can also set :counts to true in options and you'll just get the counts, eg:
      #
      # EntityCheck.find_all_split_by_freshness([60, 300], opts.merge(:counts => true)) =>
      #   {   0 => 1,
      #      60 => 3,
      #     300 => 0 }
      #
      # and you can get the last update time with each check too by passing :with_times => true eg:
      #
      # EntityCheck.find_all_split_by_freshness([60, 300], opts.merge(:with_times => true)) =>
      #   {   0 => [ ['foo-app-01:SSH', 1382329923.0] ],
      #      60 => [ ['foo-app-01:Ping', 1382329922.0], ['foo-app-01:Disk / Utilisation', 1382329921.0] ],
      #     300 => [] }
      #
      def self.find_all_split_by_freshness(ages, options)
        raise "Redis connection not set" unless redis = options[:redis]

        raise "ages does not respond_to? :each and :each_with_index" unless ages.respond_to?(:each) && ages.respond_to?(:each_with_index)
        raise "age values must respond_to? :to_i" unless ages.all? {|age| age.respond_to?(:to_i) }

        ages << 0
        ages = ages.sort.uniq

        start_time = Time.now

        checks = []
        # get all the current checks, with last update time
        Flapjack::Data::Entity.find_all_current(:redis => redis).each do |entity|
          redis.zrange("current_checks:#{entity}", 0, -1, {:withscores => true}).each do |check|
            check[0] = "#{entity}:#{check[0]}"
            checks << check
          end
        end

        skeleton = ages.inject({}) {|memo, age| memo[age] = [] ; memo }
        age_ranges = ages.reverse.each_cons(2)
        results_with_times = checks.inject(skeleton) do |memo, check|
          check_age = start_time.to_i - check[1]
          check_age = 0 unless check_age > 0
          if check_age >= ages.last
            memo[ages.last] << check
          else
            age_range = age_ranges.detect {|a, b| check_age < a && check_age >= b }
            memo[age_range.last] << check unless age_range.nil?
          end
          memo
        end

        case
        when options[:with_times]
          results_with_times
        when options[:counts]
          results_with_times.inject({}) do |memo, (age, checks)|
            memo[age] = checks.length
            memo
          end
        else
          results_with_times.inject({}) do |memo, (age, checks)|
            memo[age] = checks.map { |check| check[0] }
            memo
          end
        end
      end

      def entity_name
        entity.name
      end

      # takes a key "entity:check", returns true if the check is in unscheduled
      # maintenance
      def in_unscheduled_maintenance?
        @redis.exists("#{@key}:unscheduled_maintenance")
      end

      # returns true if the check is in scheduled maintenance
      def in_scheduled_maintenance?
        @redis.exists("#{@key}:scheduled_maintenance")
      end

      # return data about current maintenance (scheduled or unscheduled, as specified)
      def current_maintenance(opts = {})
        sched = opts[:scheduled] ? 'scheduled' : 'unscheduled'
        ts = @redis.get("#{@key}:#{sched}_maintenance")
        return unless ts
        {:start_time => ts.to_i,
         :duration   => @redis.zscore("#{@key}:#{sched}_maintenances", ts),
         :summary    => @redis.get("#{@key}:#{ts}:#{sched}_maintenance:summary"),
        }
      end

      def create_unscheduled_maintenance(start_time, duration, opts = {})
        raise ArgumentError, 'start time must be provided as a Unix timestamp' unless start_time && start_time.is_a?(Integer)
        raise ArgumentError, 'duration in seconds must be provided' unless duration && duration.is_a?(Integer) && (duration > 0)

        summary    = opts[:summary]
        time_remaining = (start_time + duration) - Time.now.to_i

        if time_remaining > 0
          end_unscheduled_maintenance(start_time) if in_unscheduled_maintenance?
          @redis.setex("#{@key}:unscheduled_maintenance", time_remaining, start_time)
        end
        @redis.zadd("#{@key}:unscheduled_maintenances", duration, start_time)
        @redis.set("#{@key}:#{start_time}:unscheduled_maintenance:summary", summary)

        @redis.zadd("#{@key}:sorted_unscheduled_maintenance_timestamps", start_time, start_time)
      end

      # ends any unscheduled maintenance
      def end_unscheduled_maintenance(end_time)
        raise ArgumentError, 'end time must be provided as a Unix timestamp' unless end_time && end_time.is_a?(Integer)

        if (um_start = @redis.get("#{@key}:unscheduled_maintenance"))
          duration = end_time - um_start.to_i
          @logger.debug("ending unscheduled downtime for #{@key} at #{Time.at(end_time).to_s}") if @logger
          @redis.del("#{@key}:unscheduled_maintenance")
          @redis.zadd("#{@key}:unscheduled_maintenances", duration, um_start) # updates existing UM 'score'
        else

          @logger.debug("end_unscheduled_maintenance called for #{@key} but none found") if @logger
        end
      end

      # creates a scheduled maintenance period for a check
      # TODO: consider adding some validation to the data we're adding in here
      # eg start_time is a believable unix timestamp (not in the past and not too
      # far in the future), duration is within some bounds...
      def create_scheduled_maintenance(start_time, duration, opts = {})
        raise ArgumentError, 'start time must be provided as a Unix timestamp' unless start_time && start_time.is_a?(Integer)
        raise ArgumentError, 'duration in seconds must be provided' unless duration && duration.is_a?(Integer) && (duration > 0)

        summary = opts[:summary]
        @redis.zadd("#{@key}:scheduled_maintenances", duration, start_time)
        @redis.set("#{@key}:#{start_time}:scheduled_maintenance:summary", summary)

        @redis.zadd("#{@key}:sorted_scheduled_maintenance_timestamps", start_time, start_time)

        # scheduled maintenance periods have changed, revalidate
        update_current_scheduled_maintenance(:revalidate => true)
      end

      # if not in scheduled maintenance, looks in scheduled maintenance list for a check to see if
      # current state should be set to scheduled maintenance, and sets it as appropriate
      def update_current_scheduled_maintenance(opts = {})
        if opts[:revalidate]
          @redis.del("#{@key}:scheduled_maintenance")
        else
          return if in_scheduled_maintenance?
        end

        # are we within a scheduled maintenance period?
        current_time = Time.now.to_i
        current_sched_ms = maintenances(nil, nil, :scheduled => true).select {|sm|
          (sm[:start_time] <= current_time) && (current_time < sm[:end_time])
        }
        return if current_sched_ms.empty?

        # yes! so set current scheduled maintenance
        # if multiple scheduled maintenances found, find the end_time furthest in the future
        most_futuristic = current_sched_ms.max {|sm| sm[:end_time] }
        start_time = most_futuristic[:start_time]
        duration   = most_futuristic[:duration]
        @redis.setex("#{@key}:scheduled_maintenance", duration.to_i, start_time)
      end

      # TODO allow summary to be changed as part of the termination
      def end_scheduled_maintenance(start_time)
        raise ArgumentError, 'start time must be supplied as a Unix timestamp' unless start_time && start_time.is_a?(Integer)

        # don't do anything if a scheduled maintenance period with that start time isn't stored
        duration = @redis.zscore("#{@key}:scheduled_maintenances", start_time)
        return false if duration.nil?

        current_time = Time.now.to_i

        if start_time > current_time
          # the scheduled maintenance period (if it exists) is in the future
          @redis.del("#{@key}:#{start_time}:scheduled_maintenance:summary")
          @redis.zrem("#{@key}:scheduled_maintenances", start_time)

          @redis.zremrangebyscore("#{@key}:sorted_scheduled_maintenance_timestamps", start_time, start_time)

          # scheduled maintenance periods (may) have changed, revalidate
          update_current_scheduled_maintenance(:revalidate => true)

          return true
        elsif (start_time + duration) > current_time
          # it spans the current time, so we'll stop it at that point
          new_duration = current_time - start_time
          @redis.zadd("#{@key}:scheduled_maintenances", new_duration, start_time)

          # scheduled maintenance periods have changed, revalidate
          update_current_scheduled_maintenance(:revalidate => true)

          return true
        end

        false
      end

      # returns nil if no previous state; this must be considered as a possible
      # state by classes using this model
      def state
        @redis.hget("check:#{@key}", 'state')
      end

      def update_state(new_state, options = {})
        return unless [STATE_OK, STATE_WARNING,
          STATE_CRITICAL, STATE_UNKNOWN].include?(new_state)

        timestamp = options[:timestamp] || Time.now.to_i
        summary = options[:summary]
        details = options[:details]
        perfdata = options[:perfdata]
        count = options[:count]

        old_state = self.state

        @redis.multi

        if old_state != new_state

          # Note the current state (for speedy lookups)
          @redis.hset("check:#{@key}", 'state', new_state)

          # FIXME: rename to last_state_change?
          @redis.hset("check:#{@key}", 'last_change', timestamp)

          case new_state
          when STATE_WARNING, STATE_CRITICAL, STATE_UNKNOWN
            @redis.zadd('failed_checks', timestamp, @key)
            # FIXME: Iterate through a list of tags associated with an entity:check pair, and update counters
          else
            @redis.zrem("failed_checks", @key)
            # FIXME: Iterate through a list of tags associated with an entity:check pair, and update counters
          end

          # Retain event data for entity:check pair
          @redis.rpush("#{@key}:states", timestamp)
          @redis.set("#{@key}:#{timestamp}:state", new_state)
          @redis.set("#{@key}:#{timestamp}:summary", summary) if summary
          @redis.set("#{@key}:#{timestamp}:details", details) if details
          @redis.set("#{@key}:#{timestamp}:count", count) if count

          @redis.zadd("#{@key}:sorted_state_timestamps", timestamp, timestamp)
        end

        # Track when we last saw an event for a particular entity:check pair
        self.last_update = timestamp

        # Even if this isn't a state change, we need to update the current state
        # hash summary and details (as they may have changed)
        @redis.hset("check:#{@key}", 'summary', (summary || ''))
        @redis.hset("check:#{@key}", 'details', (details || ''))
        if perfdata
          @redis.hset("check:#{@key}", 'perfdata', format_perfdata(perfdata).to_json)
#          @redis.set("#{@key}:#{timestamp}:perfdata", perfdata)
        end

        @redis.exec
      end

      def last_update=(timestamp)
        @redis.hset("check:#{@key}", 'last_update', timestamp)
        @redis.zadd("current_checks:#{entity.name}", timestamp, check)
        @redis.zadd('current_entities', timestamp, entity.name)
      end

      def last_update
        lu = @redis.hget("check:#{@key}", 'last_update')
        return unless lu && !!(lu =~ /^\d+$/)
        lu.to_i
      end

      # disables a check (removes currency)
      def disable!
        @logger.debug("disabling check [#{@key}]") if @logger
        @redis.zrem("current_checks:#{entity.name}", check)
        if @redis.zcount("current_checks:#{entity.name}", '-inf', '+inf') == 0
          @redis.zrem("current_checks:#{entity.name}", check)
          @redis.zrem("current_entities", entity.name)
        end
      end

      def enabled?
        !!@redis.zscore("current_checks:#{entity.name}", check)
      end

      def last_change
        lc = @redis.hget("check:#{@key}", 'last_change')
        return unless lc && !!(lc =~ /^\d+$/)
        lc.to_i
      end

      def last_notification_for_state(state)
        return unless NOTIFICATION_STATES.include?(state)
        ln = @redis.get("#{@key}:last_#{state.to_s}_notification")
        return {:timestamp => nil, :summary => nil} unless (ln && ln =~ /^\d+$/)
        { :timestamp => ln.to_i,
          :summary => @redis.get("#{@key}:#{ln.to_i}:summary") }
      end

      def last_notifications_of_each_type
        NOTIFICATION_STATES.inject({}) do |memo, state|
          memo[state] = last_notification_for_state(state) unless (state == :problem)
          memo
        end
      end

      def max_notified_severity_of_current_failure
        last_recovery = last_notification_for_state(:recovery)[:timestamp] || 0

        last_critical = last_notification_for_state(:critical)[:timestamp]
        return STATE_CRITICAL if last_critical && (last_critical > last_recovery)

        last_warning = last_notification_for_state(:warning)[:timestamp]
        return STATE_WARNING if last_warning && (last_warning > last_recovery)

        last_unknown = last_notification_for_state(:unknown)[:timestamp]
        return STATE_UNKNOWN if last_unknown && (last_unknown > last_recovery)

        nil
      end

      # unpredictable results if there are multiple notifications of different
      # types sent at the same time
      def last_notification
        nils = { :type => nil, :timestamp => nil, :summary => nil }

        lne = last_notifications_of_each_type
        ln = lne.delete_if {|type, notif| notif[:timestamp].nil? || notif[:timestamp].to_i <= 0 }
        if ln.find {|type, notif| type == :warning or type == :critical}
          ln = ln.delete_if {|type, notif| type == :problem }
        end
        return nils if ln.empty?
        lns = ln.sort_by { |type, notif| notif[:timestamp] }.last
        { :type => lns[0], :timestamp => lns[1][:timestamp], :summary => lns[1][:summary] }
      end

      def event_count_at(timestamp)
        eca = @redis.get("#{@key}:#{timestamp}:count")
        return unless (eca && eca =~ /^\d+$/)
        eca.to_i
      end

      def failed?
        [STATE_WARNING, STATE_CRITICAL, STATE_UNKNOWN].include?( state )
      end

      def ok?
        [STATE_OK].include?( state )
      end

      def summary
        @redis.hget("check:#{@key}", 'summary')
      end

      def details
        @redis.hget("check:#{@key}", 'details')
      end

      def perfdata
        data = @redis.hget("check:#{@key}", 'perfdata')
        begin
          data = JSON.parse(data) if data
        rescue
          data = "Unable to parse string: #{data}"
        end

        data = [data] if data.is_a?(Hash)
        data
      end

      # Returns a list of states for this entity check, sorted by timestamp.
      #
      # start_time and end_time should be passed as integer timestamps; these timestamps
      # will be considered inclusively, so, e.g. coverage for a day should go
      # from midnight to 11:59:59 PM. Pass nil for either end to leave that
      # side unbounded.
      def historical_states(start_time, end_time, opts = {})
        start_time = '-inf' if start_time.to_i <= 0
        end_time = '+inf' if end_time.to_i <= 0

        args = ["#{@key}:sorted_state_timestamps"]

        order = opts[:order]
        if (order && 'desc'.eql?(order.downcase))
          query = :zrevrangebyscore
          args += [end_time.to_s, start_time.to_s]
        else
          query = :zrangebyscore
          args += [start_time.to_s, end_time.to_s]
        end

        if opts[:limit] && (opts[:limit].to_i > 0)
          args << {:limit => [0, opts[:limit]]}
        end

        state_ts = @redis.send(query, *args)

        state_data = nil

        @redis.multi do |r|
          state_data = state_ts.collect {|ts|
            {:timestamp     => ts.to_i,
             :state         => r.get("#{@key}:#{ts}:state"),
             :summary       => r.get("#{@key}:#{ts}:summary"),
             :details       => r.get("#{@key}:#{ts}:details"),
             # :count         => r.get("#{@key}:#{ts}:count"),
             # :check_latency => r.get("#{@key}:#{ts}:check_latency")
            }
          }
        end

        # The redis commands in a pipeline block return future objects, which
        # must be evaluated. This relies on a patch in flapjack/patches.rb to
        # make the Future objects report their class.
        state_data.collect {|sd|
          sd.merge!(sd) {|k,ov,nv|
            (nv.class == Redis::Future) ? nv.value : nv
          }
        }
      end

      # requires a known state timestamp, i.e. probably one returned via
      # historical_states. will find the one before that in the sorted set,
      # if any.
      def historical_state_before(timestamp)
        pos = @redis.zrank("#{@key}:sorted_state_timestamps", timestamp)
        return if pos.nil? || pos < 1
        ts = @redis.zrange("#{@key}:sorted_state_timestamps", pos - 1, pos)
        return if ts.nil? || ts.empty?
        {:timestamp => ts.first.to_i,
         :state     => @redis.get("#{@key}:#{ts.first}:state"),
         :summary   => @redis.get("#{@key}:#{ts.first}:summary"),
         :details   => @redis.get("#{@key}:#{ts.first}:details")}
      end

      # Returns a list of maintenance periods (either unscheduled or scheduled) for this
      # entity check, sorted by timestamp.
      #
      # start_time and end_time should be passed as integer timestamps; these timestamps
      # will be considered inclusively, so, e.g. coverage for a day should go
      # from midnight to 11:59:59 PM. Pass nil for either end to leave that
      # side unbounded.
      def maintenances(start_time, end_time, opts = {})
        sched = opts[:scheduled] ? 'scheduled' : 'unscheduled'

        start_time ||= '-inf'
        end_time ||= '+inf'
        order = opts[:order]
        query = (order && 'desc'.eql?(order.downcase)) ? :zrevrangebyscore : :zrangebyscore
        maint_ts = @redis.send(query, "#{@key}:sorted_#{sched}_maintenance_timestamps", start_time, end_time)

        maint_data = nil

        @redis.multi do |r|
          maint_data = maint_ts.collect {|ts|
            {:start_time => ts.to_i,
             :duration   => r.zscore("#{@key}:#{sched}_maintenances", ts),
             :summary    => r.get("#{@key}:#{ts}:#{sched}_maintenance:summary"),
            }
          }
        end

        # The redis commands in a pipeline block return future objects, which
        # must be evaluated. This relies on a patch in flapjack/patches.rb to
        # make the Future objects report their class.
        maint_data.collect {|md|
          md.merge!(md) {|k,ov,nv| (nv.class == Redis::Future) ? nv.value : nv }
          md[:end_time] = (md[:start_time] + md[:duration]).floor
          md
        }
      end

      # takes a check, looks up contacts that are interested in this check (or in the check's entity)
      # and returns an array of contact records
      def contacts
        contact_ids = @redis.smembers("contacts_for:#{entity.id}:#{check}")

        if @logger
          @logger.debug("#{contact_ids.length} contact(s) for #{entity.id}:#{check}: " +
            contact_ids.inspect)
        end

        entity.contacts + contact_ids.collect {|c_id|
          Flapjack::Data::Contact.find_by_id(c_id, :redis => @redis, :logger => @logger)
        }.compact
      end

      def tags
        entity, check = @key.split(":", 2)
        ta = Flapjack::Data::TagSet.new([])
        ta += entity.split('.', 2).map {|x| x.downcase}
        ta += check.split(' ').map {|x| x.downcase}
      end

      def ack_hash
        @ack_hash ||= @redis.hget('check_hashes_by_id', @key)
        if @ack_hash.nil?
          sha1 = Digest::SHA1.new
          @ack_hash = Digest.hexencode(sha1.digest(@key))[0..7].downcase
          @redis.hset("checks_by_hash", @ack_hash, @key)
        end
        @ack_hash
      end

      def to_jsonapi(opts = {})
        {
          "name"        => @check,
          "entity_name" => @entity.name,
          "links"       => {
            :entities     => opts[:entity_ids] || [],
          }
        }.to_json
      end

    private

      def initialize(entity, check, options = {})
        raise "Redis connection not set" unless @redis = options[:redis]
        raise "Invalid entity" unless @entity = entity
        raise "Invalid check" unless @check = check
        @key = "#{entity.name}:#{check}"
        @logger = options[:logger]
      end

      def format_perfdata(perfdata)
        # example perfdata: time=0.486630s;;;0.000000 size=909B;;;0
        items = perfdata.split(' ')
        # Do some fancy regex
        data = []
        items.each do |item|
          components = item.split '='
          key = components[0].to_s
          value = ""
          if components[1]
            value = components[1].split(';')[0].to_s
          end
          data << {"key" => key, "value" => value}
        end
        data
      end

    end

  end

end
