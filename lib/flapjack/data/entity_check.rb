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

      # TODO probably shouldn't always be creating on query -- work out when this should be happening
      def self.for_event_id(event_id, options = {})
        logger = options[:logger]
        entity_name, check = event_id.split(':', 2)
        entity = Flapjack::Data::Entity.find_by_name(entity_name, :create => true, :logger => true)
        self.new(entity, check, :logger => logger)
      end

      # TODO probably shouldn't always be creating on query -- work out when this should be happening
      def self.for_entity_name(entity_name, check)
        entity = Flapjack::Data::Entity.find_by_name(entity_name, :create => true)
        self.new(entity, check)
      end

      def self.for_entity_id(entity_id, check)
        entity = Flapjack::Data::Entity.find_by_id(entity_id)
        self.new(entity, check)
      end

      def self.for_entity(entity, check)
        self.new(entity, check)
      end

      def self.find_all_for_entity_name(entity_name)
        Flapjack.redis.zrange("current_checks:#{entity_name}", 0, -1)
      end

      def self.find_all
        self.conflate_to_keys(self.find_all_by_entity)
      end

      def self.find_all_by_entity
        Flapjack.redis.zrange("current_entities", 0, -1).inject({}) {|memo, entity|
          memo[entity] = Flapjack.redis.zrange("current_checks:#{entity}", 0, -1)
          memo
        }
      end

      def self.count_all
        Flapjack.redis.zrange("current_entities", 0, -1).inject(0) {|memo, entity|
          memo + Flapjack.redis.zcount("current_checks:#{entity}", '-inf', '+inf')
        }
      end

      def self.find_all_failing
        self.conflate_to_keys(self.find_all_failing_by_entity)
      end

      def self.find_all_failing_unacknowledged(options = {})
        Flapjack.redis.zrange('failed_checks', 0, -1).reject {|entity_check|
          Flapjack.redis.exists(entity_check + ':unscheduled_maintenance')
        }
      end

      def self.find_all_failing_by_entity(options = {})
        Flapjack.redis.zrange("failed_checks", 0, -1).inject({}) do |memo, key|
          entity, check = key.split(':', 2)
          if !!Flapjack.redis.zscore("current_checks:#{entity}", check)
            memo[entity] ||= []
            memo[entity] << check
          end
          memo
        end
      end

      def self.count_all_failing(options = {})
        Flapjack.redis.zrange("failed_checks", 0, -1).count do |key|
          entity, check = key.split(':', 2)
          !!Flapjack.redis.zscore("current_checks:#{entity}", check)
        end
      end

      def self.in_unscheduled_maintenance_for_event_id?(event_id)
        Flapjack.redis.exists("#{event_id}:unscheduled_maintenance")
      end

      def self.in_scheduled_maintenance_for_event_id?(event_id)
        Flapjack.redis.exists("#{event_id}:scheduled_maintenance")
      end

      def self.state_for_event_id?(event_id)
        Flapjack.redis.hget("check:#{event_id}", 'state')
      end

      def entity_name
        entity.name
      end

      # takes a key "entity:check", returns true if the check is in unscheduled
      # maintenance
      def in_unscheduled_maintenance?
        Flapjack.redis.exists("#{@key}:unscheduled_maintenance")
      end

      # returns true if the check is in scheduled maintenance
      def in_scheduled_maintenance?
        Flapjack.redis.exists("#{@key}:scheduled_maintenance")
      end

      # return data about current maintenance (scheduled or unscheduled, as specified)
      def current_maintenance(opts = {})
        sched = opts[:scheduled] ? 'scheduled' : 'unscheduled'
        ts = Flapjack.redis.get("#{@key}:#{sched}_maintenance")
        return unless ts
        {:start_time => ts.to_i,
         :duration   => Flapjack.redis.zscore("#{@key}:#{sched}_maintenances", ts),
         :summary    => Flapjack.redis.get("#{@key}:#{ts}:#{sched}_maintenance:summary"),
        }
      end

      def create_unscheduled_maintenance(start_time, duration, opts = {})
        raise ArgumentError, 'start time must be provided as a Unix timestamp' unless start_time && start_time.is_a?(Integer)
        raise ArgumentError, 'duration in seconds must be provided' unless duration && duration.is_a?(Integer) && (duration > 0)

        summary    = opts[:summary]
        time_remaining = (start_time + duration) - Time.now.to_i
        if time_remaining > 0
          end_unscheduled_maintenance(start_time) if in_unscheduled_maintenance?
          Flapjack.redis.setex("#{@key}:unscheduled_maintenance", time_remaining, start_time)
        end
        Flapjack.redis.zadd("#{@key}:unscheduled_maintenances", duration, start_time)
        Flapjack.redis.set("#{@key}:#{start_time}:unscheduled_maintenance:summary", summary)

        Flapjack.redis.zadd("#{@key}:sorted_unscheduled_maintenance_timestamps", start_time, start_time)
      end

      # ends any unscheduled maintenance
      def end_unscheduled_maintenance(end_time)
        raise ArgumentError, 'end time must be provided as a Unix timestamp' unless end_time && end_time.is_a?(Integer)

        if (um_start = Flapjack.redis.get("#{@key}:unscheduled_maintenance"))
          duration = end_time - um_start.to_i
          @logger.debug("ending unscheduled downtime for #{@key} at #{Time.at(end_time).to_s}") if @logger
          Flapjack.redis.del("#{@key}:unscheduled_maintenance")
          Flapjack.redis.zadd("#{@key}:unscheduled_maintenances", duration, um_start) # updates existing UM 'score'
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
        Flapjack.redis.zadd("#{@key}:scheduled_maintenances", duration, start_time)
        Flapjack.redis.set("#{@key}:#{start_time}:scheduled_maintenance:summary", summary)

        Flapjack.redis.zadd("#{@key}:sorted_scheduled_maintenance_timestamps", start_time, start_time)

        # scheduled maintenance periods have changed, revalidate
        update_current_scheduled_maintenance(:revalidate => true)
      end

      # if not in scheduled maintenance, looks in scheduled maintenance list for a check to see if
      # current state should be set to scheduled maintenance, and sets it as appropriate
      def update_current_scheduled_maintenance(opts = {})
        if opts[:revalidate]
          Flapjack.redis.del("#{@key}:scheduled_maintenance")
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
        Flapjack.redis.setex("#{@key}:scheduled_maintenance", duration.to_i, start_time)
      end

      # TODO allow summary to be changed as part of the termination
      def end_scheduled_maintenance(start_time)
        raise ArgumentError, 'start time must be supplied as a Unix timestamp' unless start_time && start_time.is_a?(Integer)

        # don't do anything if a scheduled maintenance period with that start time isn't stored
        duration = Flapjack.redis.zscore("#{@key}:scheduled_maintenances", start_time)
        return false if duration.nil?

        current_time = Time.now.to_i

        if start_time > current_time
          # the scheduled maintenance period (if it exists) is in the future
          Flapjack.redis.del("#{@key}:#{start_time}:scheduled_maintenance:summary")
          Flapjack.redis.zrem("#{@key}:scheduled_maintenances", start_time)

          Flapjack.redis.zremrangebyscore("#{@key}:sorted_scheduled_maintenance_timestamps", start_time, start_time)

          # scheduled maintenance periods (may) have changed, revalidate
          update_current_scheduled_maintenance(:revalidate => true)

          return true
        elsif (start_time + duration) > current_time
          # it spans the current time, so we'll stop it at that point
          new_duration = current_time - start_time
          Flapjack.redis.zadd("#{@key}:scheduled_maintenances", new_duration, start_time)

          # scheduled maintenance periods have changed, revalidate
          update_current_scheduled_maintenance(:revalidate => true)

          return true
        end

        false
      end

      # returns nil if no previous state; this must be considered as a possible
      # state by classes using this model
      def state
        Flapjack.redis.hget("check:#{@key}", 'state')
      end

      def update_state(new_state, options = {})
        return unless [STATE_OK, STATE_WARNING,
          STATE_CRITICAL, STATE_UNKNOWN].include?(new_state)

        timestamp = options[:timestamp] || Time.now.to_i
        summary = options[:summary]
        details = options[:details]
        count = options[:count]

        old_state = self.state

        Flapjack.redis.multi

        if old_state != new_state
          # Note the current state (for speedy lookups)
          Flapjack.redis.hset("check:#{@key}", 'state', new_state)

          # FIXME: rename to last_state_change?
          Flapjack.redis.hset("check:#{@key}", 'last_change', timestamp)
          case new_state
          when STATE_WARNING, STATE_CRITICAL, STATE_UNKNOWN
            Flapjack.redis.zadd('failed_checks', timestamp, @key)
          else
            Flapjack.redis.zrem("failed_checks", @key)
          end

          # FIXME: Iterate through a list of tags associated with an entity:check pair, and update counters

          # Retain event data for entity:check pair
          Flapjack.redis.rpush("#{@key}:states", timestamp)
          Flapjack.redis.set("#{@key}:#{timestamp}:state", new_state)
          Flapjack.redis.set("#{@key}:#{timestamp}:summary", summary) if summary
          Flapjack.redis.set("#{@key}:#{timestamp}:details", details) if details
          Flapjack.redis.set("#{@key}:#{timestamp}:count", count) if count

          Flapjack.redis.zadd("#{@key}:sorted_state_timestamps", timestamp, timestamp)
        end

        # Track when we last saw an event for a particular entity:check pair
        self.last_update = timestamp

        # Even if this isn't a state change, we need to update the current state
        # hash summary and details (as they may have changed)
        Flapjack.redis.hset("check:#{@key}", 'summary', (summary || ''))
        Flapjack.redis.hset("check:#{@key}", 'details', (details || ''))

        Flapjack.redis.exec
      end

      def last_update=(timestamp)
        Flapjack.redis.hset("check:#{@key}", 'last_update', timestamp)
        Flapjack.redis.zadd("current_checks:#{entity.name}", timestamp, check)
        Flapjack.redis.zadd("current_entities", timestamp, entity.name)
      end

      def last_update
        lu = Flapjack.redis.hget("check:#{@key}", 'last_update')
        return unless lu && !!(lu =~ /^\d+$/)
        lu.to_i
      end

      # disables a check (removes currency)
      def disable!
        @logger.debug("disabling check [#{@key}]") if @logger
        Flapjack.redis.zrem("current_checks:#{entity.name}", check)
        if Flapjack.redis.zcount("current_checks:#{entity.name}", '-inf', '+inf') == 0
          Flapjack.redis.zrem("current_checks:#{entity.name}", check)
          Flapjack.redis.zrem("current_entities", entity.name)
        end
      end

      def enabled?
        !!Flapjack.redis.zscore("current_checks:#{entity.name}", check)
      end

      def last_change
        lc = Flapjack.redis.hget("check:#{@key}", 'last_change')
        return unless lc && !!(lc =~ /^\d+$/)
        lc.to_i
      end

      def last_notification_for_state(state)
        return unless NOTIFICATION_STATES.include?(state)
        ln = Flapjack.redis.get("#{@key}:last_#{state.to_s}_notification")
        return {:timestamp => nil, :summary => nil} unless (ln && ln =~ /^\d+$/)
        { :timestamp => ln.to_i,
          :summary => Flapjack.redis.get("#{@key}:#{ln.to_i}:summary") }
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
        eca = Flapjack.redis.get("#{@key}:#{timestamp}:count")
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
        timestamp = Flapjack.redis.lindex("#{@key}:states", -1)
        Flapjack.redis.get("#{@key}:#{timestamp}:summary")
      end

      def details
        timestamp = Flapjack.redis.lindex("#{@key}:states", -1)
        Flapjack.redis.get("#{@key}:#{timestamp}:details")
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

        state_ts = Flapjack.redis.send(query, *args)

        state_data = nil

        Flapjack.redis.multi do |r|
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
        pos = Flapjack.redis.zrank("#{@key}:sorted_state_timestamps", timestamp)
        return if pos.nil? || pos < 1
        ts = Flapjack.redis.zrange("#{@key}:sorted_state_timestamps", pos - 1, pos)
        return if ts.nil? || ts.empty?
        {:timestamp => ts.first.to_i,
         :state     => Flapjack.redis.get("#{@key}:#{ts.first}:state"),
         :summary   => Flapjack.redis.get("#{@key}:#{ts.first}:summary"),
         :details   => Flapjack.redis.get("#{@key}:#{ts.first}:details")}
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
        maint_ts = Flapjack.redis.send(query, "#{@key}:sorted_#{sched}_maintenance_timestamps", start_time, end_time)

        maint_data = nil

        Flapjack.redis.multi do |r|
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
        contact_ids = Flapjack.redis.smembers("contacts_for:#{entity.id}:#{check}")

        if @logger
          @logger.debug("#{contact_ids.length} contact(s) for #{entity.id}:#{check}: " +
            contact_ids.inspect)
        end

        entity.contacts + contact_ids.collect {|c_id|
          Flapjack::Data::Contact.find_by_id(c_id, :logger => @logger)
        }.compact
      end

      def tags
        entity, check = @key.split(":", 2)
        ta = Flapjack::Data::TagSet.new([])
        ta += entity.split('.', 2).map {|x| x.downcase}
        ta += check.split(' ').map {|x| x.downcase}
      end

    private

      def initialize(entity, check, options = {})
        raise "Invalid entity" unless @entity = entity
        raise "Invalid check" unless @check = check
        @key = "#{entity.name}:#{check}"
        @logger = options[:logger]
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

    end

  end

end
