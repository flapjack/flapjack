#!/usr/bin/env ruby
require 'redis'
require 'json'

def submit_event(event)
  @redis.rpush 'events', event.to_json
end

def set_scheduled_maintenance(host = 'clientx-dvmh-app-01', service = 'ping', duration = 60*60*2)
  event_id = host + ":" + service
  @redis.setex("#{event_id}:scheduled_maintenance", duration, Time.now.to_i)
  @redis.zadd("#{event_id}:scheduled_maintenances", duration, Time.now.to_i)
  @redis.set("#{event_id}:#{Time.now.to_i}:scheduled_maintenance:summary", "upgrading everything")
end

def remove_scheduled_maintenance(host = 'clientx-dvmh-app-01', service = 'ping')
  event_id = host + ":" + service
  @redis.del("#{event_id}:scheduled_maintenance")
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

def remove_notifications(host = 'clientx-dvmh-app-01', service = 'ping')
  event_id = host + ":" + service
  @redis.del("#{event_id}:last_problem_notification")
  @redis.del("#{event_id}:last_recovery_notification")
  @redis.del("#{event_id}:last_acknowledgement_notification")
end

def set_ok_state(host = 'clientx-dvmh-app-01', service = 'ping')
  event_id = host + ":" + service
  @redis.hset(event_id, 'state', 'ok')
  @redis.hset(event_id, 'last_change', (Time.now.to_i - (60*60*24)))
  @redis.zrem('failed_services', event_id)
  @redis.zrem('failed_services:client:clientx', event_id)
end

def set_failure_state(host = 'clientx-dvmh-app-01', service = 'ping')
  event_id = host + ":" + service
  @redis.hset(event_id, 'state', 'critical')
  @redis.hset(event_id, 'last_change', (Time.now.to_i - (60*60*24)))
  @redis.zadd('failed_services', (Time.now.to_i - (60*60*24)), event_id)
  @redis.zadd('failed_services:client:clientx', (Time.now.to_i - (60*60*24)), event_id)
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
  @app.process_events
end

Given /^service x is in an ok state$/ do
  remove_unscheduled_maintenance
  remove_scheduled_maintenance
  remove_notifications
  set_ok_state
end

Given /^service x is in a failure state$/ do
  remove_unscheduled_maintenance
  remove_scheduled_maintenance
  remove_notifications
  set_failure_state
end

Given /^service x is in scheduled maintenance$/ do
  remove_unscheduled_maintenance
  set_scheduled_maintenance
end

Given /^service x is in unscheduled maintenance$/ do
  remove_scheduled_maintenance
  set_failure_state
  submit_acknowledgement
  process_events
end

When /^an ok event is received for service x$/ do
  submit_ok
  process_events
end

Then /^a notification should not be generated for service x$/ do
  $notification.should =~ /Not sending notifications for event/
end

Then /^a notification should be generated for service x$/ do
  process_events
  $notification.should =~ /Sending notifications for event/
end

When /^a failure event is received for service x$/ do
  submit_critical
  process_events
end

When /^an acknowledgement is received for service x$/ do
  submit_acknowledgement
  process_events
end

When /^an acknowledgement event is received for service x$/ do
  submit_acknowledgement
  process_events
end

Then /^show me the notification$/ do
  puts $notification
end

