#!/usr/bin/env ruby

require 'redis'
require 'json'

id = "%.2d" % (1..10).to_a[rand(9)]

events = []

events << {
  'host' => "app-#{id}",
  'service' => 'http',
  'type' => 'service',
  'state' => 'ok',
}.to_json

events << {
  'host' => "app-#{id}",
  'service' => 'http',
  'type' => 'service',
  'state' => 'critical',
}.to_json

events << {
  'host' => "app-#{id}",
  'service' => 'http',
  'type' => 'action',
  'state' => 'acknowledgement',
}.to_json

events << {
  'host' => "app-#{id}",
  'service' => 'http',
  'type' => 'service',
  'state' => 'ok',
}.to_json

redis = Redis.new

1.times do
  events.each {|event|
    redis.rpush 'events', event
  }
end
