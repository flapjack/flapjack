#!/usr/bin/env ruby

require 'redis'

require 'oj'
Oj.mimic_JSON
Oj.default_options = { :indent => 0, :mode => :compat }
require 'active_support/json'

id = "%.2d" % (1..10).to_a[rand(9)]

events = []

events << Oj.dump({
  'entity' => "app-#{id}",
  'check' => 'http',
  'type' => 'service',
  'state' => 'ok',
  'summary' => 'well i don\'t know',
})

events << Oj.dump({
  'entity' => "app-#{id}",
  'check' => 'http',
  'type' => 'host',
  'state' => 'critical',
  'summary' => 'well i don\'t know',
})

redis = Redis.new(:db => 13)

2000.times do
  events.each {|event|
    redis.rpush 'events', event
  }
end

puts "#{Time.now} - finished loading up events"
previous_events_size = redis.llen 'events'
while previous_events_size > 0
  sleep 1
  events_size = redis.llen 'events'
  throughput = previous_events_size - events_size
  previous_events_size = events_size
  puts "#{Time.now} - #{events_size} (#{throughput})"
end
