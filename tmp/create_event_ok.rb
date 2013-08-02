#!/usr/bin/env ruby

require 'redis'

require 'oj'
Oj.default_options = { :indent => 0, :mode => :strict }

#id = "%.2d" % (1..10).to_a[rand(9)]

events = []

events << {
  'entity' => "client1-localhost-test-1",
  'check' => 'foo',
  'type' => 'service',
  'state' => 'ok',
}.to_json

redis = Redis.new(:db => 13)

events.each {|event|
  redis.rpush 'events', event
}

puts "#{Time.now} - finished loading up events"
previous_events_size = redis.llen 'events'
while previous_events_size > 0
  sleep 1
  events_size = redis.llen 'events'
  throughput = previous_events_size - events_size
  previous_events_size = events_size
  puts "#{Time.now} - #{events_size} (#{throughput})"
end
