#!/usr/bin/env ruby

require 'yajl/json_gem'

require 'flapjack/patches'

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

      attr_accessor :entity, :check

      # TODO probably shouldn't always be creating on query -- work out when this should be happening
      def self.for_event_id(event_id, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        entity_name, check = event_id.split(':')
        self.new(Flapjack::Data::Entity.find_by_name(entity_name, :redis => redis, :create => true), check,
          :redis => redis)
      end

      # TODO probably shouldn't always be creating on query -- work out when this should be happening
      def self.for_entity_name(entity_name, check, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        self.new(Flapjack::Data::Entity.find_by_name(entity_name, :redis => redis, :create => true), check,
          :redis => redis)
      end

      def self.for_entity_id(entity_id, check, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        self.new(Flapjack::Data::Entity.find_by_id(entity_id, :redis => redis), check,
          :redis => redis)
      end

      def self.for_entity(entity, check, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        self.new(entity, check, :redis => redis)
      end

      def entity_name
        @entity.name
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
      def current_maintenance(opts)
        sched = opts[:scheduled] ? 'scheduled' : 'unscheduled'
        ts = @redis.get("#{@key}:#{sched}_maintenance")
        return unless ts
        {:start_time => ts.to_i,
         :duration   => @redis.zscore("#{@key}:#{sched}_maintenances", ts),
         :summary    => @redis.get("#{@key}:#{ts}:#{sched}_maintenance:summary"),
        }
      end

      def create_acknowledgement(options = {})
        event = { 'type'               => 'action',
                  'state'              => 'acknowledgement',
                  'summary'            => options['summary'],
                  'duration'           => options['duration'],
                  'acknowledgement_id' => options['acknowledgement_id'],
                  'entity'             => @entity.name,
                  'check'              => @check
                }
        Flapjack::Data::Event.create(event, :redis => @redis)
      end

      # FIXME: need to add summary to summary of existing unscheduled maintenance if there is
      # one, and extend duration / expiry time, instead of creating a separate unscheduled
      # outage as we are doing now...
      def create_unscheduled_maintenance(opts = {})
        start_time = opts[:start_time]  # unix timestamp
        duration   = opts[:duration]    # seconds
        summary    = opts[:summary]
        time_remaining = (start_time + duration) - Time.now.to_i
        if time_remaining > 0
          @redis.setex("#{@key}:unscheduled_maintenance", time_remaining, start_time)
        end
        @redis.zadd("#{@key}:unscheduled_maintenances", duration, start_time)
        @redis.set("#{@key}:#{start_time}:unscheduled_maintenance:summary", summary)

        @redis.zadd("#{@key}:sorted_unscheduled_maintenance_timestamps", start_time, start_time)
      end

      # ends any unscheduled maintenance
      def end_unscheduled_maintenance(opts = {})
        defaults = {
          :end_time => Time.now.to_i
        }
        options  = defaults.merge(opts)
        end_time = options[:end_time]

        if (um_start = @redis.get("#{@key}:unscheduled_maintenance"))
          duration = end_time - um_start.to_i
          @logger.debug("ending unscheduled downtime for #{@key} at #{Time.at(end_time).to_s}") if @logger
          @redis.del("#{@key}:unscheduled_maintenance")
          @redis.zadd("#{@key}:unscheduled_maintenances", duration, um_start)
          @redis.zadd("#{@key}:sorted_unscheduled_maintenance_timestamps", um_start, um_start)
        else
          @logger.debug("end_unscheduled_maintenance called for #{@key} but none found") if @logger
        end
      end

      # creates a scheduled maintenance period for a check
      # TODO: consider adding some validation to the data we're adding in here
      # eg start_time is a believable unix timestamp (not in the past and not too
      # far in the future), duration is within some bounds...
      def create_scheduled_maintenance(opts = {})
        start_time = opts[:start_time]  # unix timestamp
        duration   = opts[:duration]    # seconds
        summary    = opts[:summary]
        @redis.zadd("#{@key}:scheduled_maintenances", duration, start_time)
        @redis.set("#{@key}:#{start_time}:scheduled_maintenance:summary", summary)

        @redis.zadd("#{@key}:sorted_scheduled_maintenance_timestamps", start_time, start_time)

        # scheduled maintenance periods have changed, revalidate
        update_current_scheduled_maintenance(:revalidate => true)
      end

      # change the end time of a scheduled maintenance (including when one is current)
      def update_scheduled_maintenance(start_time, patches = {})

        # check if there is such a scheduled maintenance period
        old_duration = @redis.zscore("#{@key}:scheduled_maintenances", start_time)
        raise ArgumentError, 'no such scheduled maintenance period can be found' unless old_duration
        raise ArgumentError, 'no handled patches have been supplied' unless patches[:end_time]

        if patches[:end_time]
          end_time = patches[:end_time]
          raise ArgumentError unless end_time > start_time
          old_end_time = start_time + old_duration
          duration = end_time - start_time
          @redis.zadd("#{@key}:scheduled_maintenances", duration, start_time)
        end

        # scheduled maintenance periods have changed, revalidate
        update_current_scheduled_maintenance(:revalidate => true)

      end

      # delete a scheduled maintenance
      def delete_scheduled_maintenance(opts = {})
        start_time = opts[:start_time]
        @redis.del("#{@key}:#{start_time}:scheduled_maintenance:summary")
        @redis.zrem("#{@key}:scheduled_maintenances", start_time)

        @redis.zremrangebyscore("#{@key}:sorted_scheduled_maintenance_timestamps", start_time, start_time)

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
        t = Time.now.to_i
        current_sched_ms = maintenances(nil, nil, :scheduled => true).select {|sm|
          (sm[:start_time] <= t) && (t < sm[:end_time])
        }
        return if current_sched_ms.empty?

        # yes! so set current scheduled maintenance
        # if multiple scheduled maintenances found, find the end_time furthest in the future
        most_futuristic = current_sched_ms.max {|sm| sm[:end_time] }
        start_time = most_futuristic[:start_time]
        duration   = most_futuristic[:duration]
        @redis.setex("#{@key}:scheduled_maintenance", duration.to_i, start_time)
      end

      # returns nil if no previous state; this must be considered as a possible
      # state by classes using this model
      def state
        @redis.hget("check:#{@key}", 'state')
      end

      def update_state(state, options = {})
        return unless validate_state(state)
        timestamp = options[:timestamp] || Time.now.to_i
        client = options[:client]
        summary = options[:summary]
        count = options[:count]

        # Note the current state (for speedy lookups)
        @redis.hset("check:#{@key}", 'state', state)

        # FIXME: rename to last_state_change?
        @redis.hset("check:#{@key}", 'last_change', timestamp)

        # Retain all state changes for entity:check pair
        @redis.rpush("#{@key}:states", timestamp)
        @redis.set("#{@key}:#{timestamp}:state",   state)
        @redis.set("#{@key}:#{timestamp}:summary", summary) if summary
        @redis.set("#{@key}:#{timestamp}:count", count) if count

        @redis.zadd("#{@key}:sorted_state_timestamps", timestamp, timestamp)

        case state
        when STATE_WARNING, STATE_CRITICAL
          @redis.zadd('failed_checks', timestamp, @key)
          # FIXME: Iterate through a list of tags associated with an entity:check pair, and update counters
          @redis.zadd("failed_checks:client:#{client}", timestamp, @key) if client
        else
          @redis.zrem("failed_checks", @key)
          # FIXME: Iterate through a list of tags associated with an entity:check pair, and update counters
          @redis.zrem("failed_checks:client:#{client}", @key) if client
        end
      end

      def last_update
        lu = @redis.hget("check:#{@key}", 'last_update')
        return unless (lu && lu =~ /^\d+$/)
        lu.to_i
      end

      def last_update=(timestamp)
        @redis.hset("check:#{@key}", 'last_update', timestamp)
      end

      def last_change
        lc = @redis.hget("check:#{@key}", 'last_change')
        return unless (lc && lc =~ /^\d+$/)
        lc.to_i
      end

      def last_problem_notification
        lpn = @redis.get("#{@key}:last_problem_notification")
        return unless (lpn && lpn =~ /^\d+$/)
        lpn.to_i
      end

      def last_recovery_notification
        lrn = @redis.get("#{@key}:last_recovery_notification")
        return unless (lrn && lrn =~ /^\d+$/)
        lrn.to_i
      end

      def last_acknowledgement_notification
        lan = @redis.get("#{@key}:last_acknowledgement_notification")
        return unless (lan && lan =~ /^\d+$/)
        lan.to_i
      end

      def last_notifications_of_each_type
        ln = {:problem         => last_problem_notification,
              :recovery        => last_recovery_notification,
              :acknowledgement => last_acknowledgement_notification }
        ln
      end

      # unpredictable results if there are multiple notifications of different
      # types sent at the same time
      def last_notification
        nils = { :type => nil, :timestamp => nil }
        lne = last_notifications_of_each_type
        ln = lne.delete_if {|type, timestamp|
          timestamp.nil? || timestamp.to_i == 0
        }
        return nils unless ln.length > 0
        lns = ln.sort_by { |type, timestamp| timestamp }.last
        { :type => lns[0], :timestamp => lns[1] }
      end

      def event_count_at(timestamp)
        eca = @redis.get("#{@key}:#{timestamp}:count")
        return unless (eca && eca =~ /^\d+$/)
        eca.to_i
      end

      def failed?
        [STATE_WARNING, STATE_CRITICAL].include?( state )
      end

      def ok?
        [STATE_OK].include?( state )
      end

      def summary
        timestamp = @redis.lindex("#{@key}:states", -1)
        @redis.get("#{@key}:#{timestamp}:summary")
      end

      # Returns a list of states for this entity check, sorted by timestamp.
      #
      # start_time and end_time should be passed as integer timestamps; these timestamps
      # will be considered inclusively, so, e.g. coverage for a day should go
      # from midnight to 11:59:59 PM. Pass nil for either end to leave that
      # side unbounded.
      def historical_states(start_time, end_time, opts = {})
        start_time ||= '-inf'
        end_time ||= '+inf'
        order = opts[:order]
        query = (order && 'desc'.eql?(order.downcase)) ? :zrevrangebyscore : :zrangebyscore
        state_ts = @redis.send(query, "#{@key}:sorted_state_timestamps", start_time, end_time)

        state_data = nil

        @redis.multi do |r|
          state_data = state_ts.collect {|ts|
            {:timestamp => ts.to_i,
             :state     => r.get("#{@key}:#{ts}:state"),
             :summary   => r.get("#{@key}:#{ts}:summary")}
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
        return if pos < 1
        ts = @redis.zrange("#{@key}:sorted_state_timestamps", pos - 1, pos)
        return if ts.nil? || ts.empty?
        {:timestamp => ts.first.to_i,
         :state     => @redis.get("#{@key}:#{ts.first}:state"),
         :summary   => @redis.get("#{@key}:#{ts.first}:summary")}
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

      # returns an array of pagerduty credentials. If more than one contact for this entity_check
      # has pagerduty credentials then there'll be one hash in the array for each set of
      # credentials.
      def pagerduty_credentials(options)
        # raise "Redis connection not set" unless redis = options[:redis]

        self.contacts.inject([]) {|ret, contact|
          cred = contact.pagerduty_credentials
          ret << cred if cred
          ret
        }
      end

      # takes a check, looks up contacts that are interested in this check (or in the check's entity)
      # and returns an array of contact records
      def contacts
        entity = @entity
        check  = @check

        if @logger
          @logger.debug("contacts for #{@entity.id} (#{@entity.name}): " +
            @redis.smembers("contacts_for:#{@entity.id}").length.to_s)
          @logger.debug("contacts for #{check}: " +
            @redis.smembers("contacts_for:#{check}").length.to_s)
        end

        union = @redis.sunion("contacts_for:#{@entity.id}", "contacts_for:#{check}")
        @logger.debug("contacts for union of #{@entity.id} and #{check}: " + union.length.to_s) if @logger
        union.collect {|c_id| Flapjack::Data::Contact.find_by_id(c_id, :redis => @redis) }
      end

    private

      def initialize(entity, check, options = {})
        raise "Redis connection not set" unless @redis = options[:redis]
        raise "Invalid entity" unless @entity = entity
        raise "Invalid check" unless @check = check
        @key = "#{entity.name}:#{check}"
      end

      def validate_state(state)
        [STATE_OK, STATE_WARNING, STATE_CRITICAL, STATE_UNKNOWN].include?(state)
      end

    end

  end

end
