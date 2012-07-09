#!/usr/bin/env ruby

require 'redis'
require 'json'

id = "%.2d" % (1..10).to_a[rand(9)]

event = {
  'host' => "app-#{id}",
  'service' => 'http',
  'type' => 'service',
  'state' => 'critical',
}.to_json

redis = Redis.new

5.times do
  redis.rpush 'events', event
end
