#!/usr/bin/env ruby
require 'redis'
require 'json'

def submit_event(event)
  @redis.rpush 'events', event.to_json
end

def remove_unscheduled_maintenance(host = 'clientx-dvmh-app-01', service = 'ping')
  # end any unscheduled downtime
  event_id = host + ":" + service
  if (um_start = @redis.get("#{event_id}:unscheduled_maintenance"))
    @redis.del("#{event_id}:unscheduled_maintenance")
    duration = Time.now.to_i - um_start.to_i
    @redis.zadd("#{event_id}:unscheduled_maintenances", duration, um_start)
  end
end

def submit_ok(host = 'clientx-dvmh-app-01', service = 'ping')
  event = {
    'type'    => 'service',
    'state'   => 'ok',
    'summary' => '0% packet loss',
    'host'    => host,
    'service' => service,
  }
  submit_event(event)
end

def submit_critical(host = 'clientx-dvmh-app-01', service = 'ping')
  event = {
    'type'    => 'service',
    'state'   => 'critical',
    'summary' => '100% packet loss',
    'host'    => host,
    'service' => service,
  }
  submit_event(event)
end

def submit_acknowledgement(host = 'clientx-dvmh-app-01', service = 'ping')
  event = {
    'type'    => 'action',
    'state'   => 'acknowledgement',
    'summary' => "I'll have this fixed in a jiffy, saw the same thing yesterday",
    'host'    => host,
    'service' => service,
  }
  submit_event(event)
end


def process_events
  @output = `tmp/process_events.rb`
end


Given /^service x is in an ok state$/ do
  remove_unscheduled_maintenance
  submit_ok
  process_events
end

When /^an ok event is received for service x$/ do
  submit_ok
end

Then /^a notification should not be generated for service x$/ do
  process_events
  @output.should =~ /Not sending notifications for event/
end

Then /^a notification should be generated for service x$/ do
  process_events
  @output.should =~ /Sending notifications for event/
end

When /^a failure event is received for service x$/ do
  submit_critical
end

Given /^service x is in scheduled maintenance$/ do
  pending # express the regexp above with the code you wish you had
end

Given /^service x is in unscheduled maintenance$/ do
  submit_ok
  submit_critical
  submit_acknowledgement
  process_events
end

When /^an acknowledgement is received for service x$/ do
  submit_acknowledgement
end

Given /^service x is in a failure state$/ do
  clear_unscheduled_maintenance
  submit_critical
  process_events
end

When /^an acknowledgement event is received for service x$/ do
  submit_acknowledgement
end

Then /^show me the fucking output$/ do
  puts @output
end

