#!/usr/bin/env ruby

require 'delorean'
require 'chronic'
require 'active_support/time'

When /^(.+) passes$/ do |time|
  period = Chronic.parse("#{time} from now")
  RedisDelorean.time_travel_to(period)
  #puts "Time Travelled to #{Time.now.to_s}"
end

# Given /^I time travel to (.+)$/ do |period|
#   RedisDelorean.time_travel_to(period)
#   # puts "Time Travelled to #{Time.now.to_s}"
# end

Given /^the timezone is (.*)$/ do |tz|
  Time.zone = tz
  Chronic.time_class = Time.zone
end

Given /^the time is (.*)$/ do |time|
  RedisDelorean.time_travel_to(Chronic.parse("#{time}"))
  #puts "Time Travelled to #{Time.now.to_s}"
end

# Given /^I come back to the present$/ do
#   RedisDelorean.back_to_the_present
#   # puts "Time Travelled to the present, #{Time.now.to_s}"
# end

# Given /^I time travel in (.+) to (.+)$/ do |zone_name, timestamp|
#   zone = ::Time.find_zone!(zone_name)
#   time = zone.parse timestamp
#   RedisDelorean.time_travel_to time
#   # puts "Time Travelled to #{Time.now.to_s}"
# end

# Then /^the time in UTC should be about (.+)$/ do |timestamp|
#   actual = Time.now.in_time_zone('UTC')
#   expected = Time.parse("#{timestamp} UTC")
#   (expected..expected+5).cover?(actual).should be true
# end

