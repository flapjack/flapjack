#!/usr/bin/env ruby

$: << File.dirname(__FILE__) + '/../lib' unless $:.include?(File.dirname(__FILE__) + '/../lib/')

require 'redis'

@dry_run = false

@redis = Redis.new(:db => 0)

state_lists = @redis.keys("*:*:states")

puts "#{state_lists.length} state lists found"

ts_deletions = 0
state_deletions = 0

state_lists.each {|state_list|
  times = @redis.lrange(state_list, 0, -1)
  key   = state_list.sub(/:states$/, '')
  #puts "--> #{key} - #{times.length} state changes"

  last_timestamp = ''
  last_state = ''
  times.each {|ts|
    t = Time.at(ts.to_i)
    raise "Timestamps went backwards!" if ts.to_i < last_timestamp.to_i
    state = @redis.get("#{key}:#{ts}:state")
    delete_ts = (ts == last_timestamp) ? true : false
    delete_ts_message = "DELETE_TS" if delete_ts
    delete_state = (state == last_state) ? true : false
    delete_state_message = "DELETE_STATE" if delete_state
    puts "----> #{key} #{t} #{state} #{delete_ts_message} #{delete_state_message}" if delete_ts || delete_state
    unless @dry_run
      @redis.lrem("#{key}:states", 1, ts) if delete_ts
      if delete_state
        @redis.lrem("#{key}:states", 0, ts)
        @redis.zrem("#{key}:sorted_state_timestamps", ts)
        @redis.del("#{key}:#{ts}:state")
        @redis.del("#{key}:#{ts}:summary")
        @redis.del("#{key}:#{ts}:count")
        @redis.del("#{key}:#{ts}:check_latency")
      end
    end
    ts_deletions += 1 if delete_ts
    state_deletions += 1 if delete_state
    last_timestamp = ts
    last_state = state
  }
}

puts "Summary: #{ts_deletions} duplicate timestamp deletions deleted, #{state_deletions} duplicated states deleted"
