#!/usr/bin/env ruby

require 'redis'

require 'oj'
Oj.default_options = { :indent => 0, :mode => :strict }

if not id = ARGV.first then
  puts "Usage: acknowledge.rb <id>"
  exit 1
end


redis = Redis.new

redis.hset 'acknowledged', id, 'true'
