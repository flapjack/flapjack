#!/usr/bin/env ruby

require 'delorean'
require 'chronic'
require 'active_support/time'

When /^(.+) passes$/ do |time|
  period = Chronic.parse("#{time} from now")
  RedisDelorean.time_travel_to(period)
end

Given /^the timezone is (.*)$/ do |tz|
  Time.zone = tz
  Chronic.time_class = Time.zone
end

Given /^the time is (.*)$/ do |time|
  RedisDelorean.time_travel_to(Chronic.parse("#{time}"))
end
