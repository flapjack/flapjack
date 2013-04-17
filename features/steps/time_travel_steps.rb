#!/usr/bin/env ruby

require 'delorean'
require 'chronic'

When /^(.+) passes$/ do |time|
  period = Chronic.parse("#{time} from now")
  Delorean.time_travel_to(period)
  # puts "Time Travelled to #{Time.now.to_s}"
end

# Given /^I time travel to (.+)$/ do |period|
#   Delorean.time_travel_to(period)
#   # puts "Time Travelled to #{Time.now.to_s}"
# end

# Given /^I come back to the present$/ do
#   Delorean.back_to_the_present
#   # puts "Time Travelled to the present, #{Time.now.to_s}"
# end

# Given /^I time travel in (.+) to (.+)$/ do |zone_name, timestamp|
#   zone = ::Time.find_zone!(zone_name)
#   time = zone.parse timestamp
#   Delorean.time_travel_to time
#   # puts "Time Travelled to #{Time.now.to_s}"
# end

# Then /^the time in UTC should be about (.+)$/ do |timestamp|
#   actual = Time.now.in_time_zone('UTC')
#   expected = Time.parse("#{timestamp} UTC")
#   (expected..expected+5).cover?(actual).should be_true
# end

