#!/usr/bin/env ruby

module Flapjack
  module Data
    class CheckStateR

      include Flapjack::Data::RedisRecord

      STATE_OK       = 'ok'
      STATE_WARNING  = 'warning'
      STATE_CRITICAL = 'critical'
      STATE_UNKNOWN  = 'unknown'

      def self.ok_states
        [STATE_OK]
      end

      def self.failing_states
        [STATE_WARNING, STATE_CRITICAL, STATE_UNKNOWN]
      end

      # moved, WIP
      # def self.update_state(entity_check, new_state, options = {})
      #   return unless [STATE_OK, STATE_WARNING,
      #     STATE_CRITICAL, STATE_UNKNOWN].include?(new_state)

      #   timestamp = options[:timestamp] || Time.now.to_i
      #   summary = options[:summary]
      #   details = options[:details]
      #   count = options[:count]

      #   if entity_check.state != new_state
      #     entity_check.state = new_state
      #   end

      # end

  #     def update_state(new_state, options = {})
  #       return unless [STATE_OK, STATE_WARNING,
  #         STATE_CRITICAL, STATE_UNKNOWN].include?(new_state)

  #       timestamp = options[:timestamp] || Time.now.to_i
  #       summary = options[:summary]
  #       details = options[:details]
  #       count = options[:count]

  #       old_state = self.state

  #       Flapjack.redis.multi

  #       if old_state != new_state
  #         # Note the current state (for speedy lookups)
  #         Flapjack.redis.hset("check:#{@key}", 'state', new_state)

  #         # FIXME: rename to last_state_change?
  #         Flapjack.redis.hset("check:#{@key}", 'last_change', timestamp)
  #         case new_state
  #         when STATE_WARNING, STATE_CRITICAL, STATE_UNKNOWN
  #           Flapjack.redis.zadd('failed_checks', timestamp, @key)
  #         else
  #           Flapjack.redis.zrem("failed_checks", @key)
  #         end

  #         # FIXME: Iterate through a list of tags associated with an entity:check pair, and update counters

  #         # Retain event data for entity:check pair
  #         Flapjack.redis.rpush("#{@key}:states", timestamp)
  #         Flapjack.redis.set("#{@key}:#{timestamp}:state", new_state)
  #         Flapjack.redis.set("#{@key}:#{timestamp}:summary", summary) if summary
  #         Flapjack.redis.set("#{@key}:#{timestamp}:details", details) if details
  #         Flapjack.redis.set("#{@key}:#{timestamp}:count", count) if count

  #         Flapjack.redis.zadd("#{@key}:sorted_state_timestamps", timestamp, timestamp)
  #       end

  #       # Track when we last saw an event for a particular entity:check pair

  #       Flapjack.redis.hset("check:#{@key}", 'last_update', timestamp)
  #       Flapjack.redis.zadd("current_checks:#{entity.name}", timestamp, check)
  #       Flapjack.redis.zadd("current_entities", timestamp, entity.name)

  #       # Even if this isn't a state change, we need to update the current state
  #       # hash summary and details (as they may have changed)
  #       Flapjack.redis.hset("check:#{@key}", 'summary', (summary || ''))
  #       Flapjack.redis.hset("check:#{@key}", 'details', (details || ''))

  #       Flapjack.redis.exec
  #     end

  #     def last_update
  #       lu = Flapjack.redis.hget("check:#{@key}", 'last_update')
  #       return unless lu && !!(lu =~ /^\d+$/)
  #       lu.to_i
  #     end

  #     # Returns a list of states for this entity check, sorted by timestamp.
  #     #
  #     # start_time and end_time should be passed as integer timestamps; these timestamps
  #     # will be considered inclusively, so, e.g. coverage for a day should go
  #     # from midnight to 11:59:59 PM. Pass nil for either end to leave that
  #     # side unbounded.
  #     def historical_states(start_time, end_time, opts = {})
  #       start_time = '-inf' if start_time.to_i <= 0
  #       end_time = '+inf' if end_time.to_i <= 0

  #       args = ["#{@key}:sorted_state_timestamps"]

  #       order = opts[:order]
  #       if (order && 'desc'.eql?(order.downcase))
  #         query = :zrevrangebyscore
  #         args += [end_time.to_s, start_time.to_s]
  #       else
  #         query = :zrangebyscore
  #         args += [start_time.to_s, end_time.to_s]
  #       end

  #       if opts[:limit] && (opts[:limit].to_i > 0)
  #         args << {:limit => [0, opts[:limit]]}
  #       end

  #       state_ts = Flapjack.redis.send(query, *args)

  #       state_data = nil

  #       Flapjack.redis.multi do |r|
  #         state_data = state_ts.collect {|ts|
  #           {:timestamp     => ts.to_i,
  #            :state         => r.get("#{@key}:#{ts}:state"),
  #            :summary       => r.get("#{@key}:#{ts}:summary"),
  #            :details       => r.get("#{@key}:#{ts}:details"),
  #            # :count         => r.get("#{@key}:#{ts}:count"),
  #            # :check_latency => r.get("#{@key}:#{ts}:check_latency")
  #           }
  #         }
  #       end

  #       # The redis commands in a pipeline block return future objects, which
  #       # must be evaluated. This relies on a patch in flapjack/patches.rb to
  #       # make the Future objects report their class.
  #       state_data.collect {|sd|
  #         sd.merge!(sd) {|k,ov,nv|
  #           (nv.class == Redis::Future) ? nv.value : nv
  #         }
  #       }
  #     end

  #     # requires a known state timestamp, i.e. probably one returned via
  #     # historical_states. will find the one before that in the sorted set,
  #     # if any.
  #     def historical_state_before(timestamp)
  #       pos = Flapjack.redis.zrank("#{@key}:sorted_state_timestamps", timestamp)
  #       return if pos.nil? || pos < 1
  #       ts = Flapjack.redis.zrange("#{@key}:sorted_state_timestamps", pos - 1, pos)
  #       return if ts.nil? || ts.empty?
  #       {:timestamp => ts.first.to_i,
  #        :state     => Flapjack.redis.get("#{@key}:#{ts.first}:state"),
  #        :summary   => Flapjack.redis.get("#{@key}:#{ts.first}:summary"),
  #        :details   => Flapjack.redis.get("#{@key}:#{ts.first}:details")}
  #     end

  #     # Returns a list of maintenance periods (either unscheduled or scheduled) for this
  #     # entity check, sorted by timestamp.
  #     #
  #     # start_time and end_time should be passed as integer timestamps; these timestamps
  #     # will be considered inclusively, so, e.g. coverage for a day should go
  #     # from midnight to 11:59:59 PM. Pass nil for either end to leave that
  #     # side unbounded.
  #     def maintenances(start_time, end_time, opts = {})
  #       sched = opts[:scheduled] ? 'scheduled' : 'unscheduled'

  #       start_time ||= '-inf'
  #       end_time ||= '+inf'
  #       order = opts[:order]
  #       query = (order && 'desc'.eql?(order.downcase)) ? :zrevrangebyscore : :zrangebyscore
  #       maint_ts = Flapjack.redis.send(query, "#{@key}:sorted_#{sched}_maintenance_timestamps", start_time, end_time)

  #       maint_data = nil

  #       Flapjack.redis.multi do |r|
  #         maint_data = maint_ts.collect {|ts|
  #           {:start_time => ts.to_i,
  #            :duration   => r.zscore("#{@key}:#{sched}_maintenances", ts),
  #            :summary    => r.get("#{@key}:#{ts}:#{sched}_maintenance:summary"),
  #           }
  #         }
  #       end

  #       # The redis commands in a pipeline block return future objects, which
  #       # must be evaluated. This relies on a patch in flapjack/patches.rb to
  #       # make the Future objects report their class.
  #       maint_data.collect {|md|
  #         md.merge!(md) {|k,ov,nv| (nv.class == Redis::Future) ? nv.value : nv }
  #         md[:end_time] = (md[:start_time] + md[:duration]).floor
  #         md
  #       }
  #     end


    end
  end
end