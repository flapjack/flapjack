#!/usr/bin/env ruby

require 'redis'
require 'json'

id = "%.2d" % (1..10).to_a[rand(9)]

events = []

events << {
  'entity'    => "app-#{id}",
  'check'     => 'http',
  'type'      => 'service',
  'state'     => 'critical',
  'summary'   => "It's failing, yo!",
  'timestamp' => Time.now.to_i,
}.to_json

redis = Redis.new

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
