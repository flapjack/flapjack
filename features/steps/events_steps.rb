#!/usr/bin/env ruby
require 'redis'
require 'json'

def submit_event(event)
  @redis.rpush 'events', event.to_json
end

def set_scheduled_maintenance(entity = 'clientx-dvmh-app-01', check = 'ping', duration = 60*60*2)
  event_id = entity + ":" + check
  @redis.setex("#{event_id}:scheduled_maintenance", duration, Time.now.to_i)
  @redis.zadd("#{event_id}:scheduled_maintenances", duration, Time.now.to_i)
  @redis.set("#{event_id}:#{Time.now.to_i}:scheduled_maintenance:summary", "upgrading everything")
end

def remove_scheduled_maintenance(entity = 'clientx-dvmh-app-01', check = 'ping')
  event_id = entity + ":" + check
  @redis.del("#{event_id}:scheduled_maintenance")
end

def remove_unscheduled_maintenance(entity = 'clientx-dvmh-app-01', check = 'ping')
  # end any unscheduled downtime
  event_id = entity + ":" + check
  if (um_start = @redis.get("#{event_id}:unscheduled_maintenance"))
    @redis.del("#{event_id}:unscheduled_maintenance")
    duration = Time.now.to_i - um_start.to_i
    @redis.zadd("#{event_id}:unscheduled_maintenances", duration, um_start)
  end
end

def remove_notifications(entity = 'clientx-dvmh-app-01', check = 'ping')
  event_id = entity + ":" + check
  @redis.del("#{event_id}:last_problem_notification")
  @redis.del("#{event_id}:last_recovery_notification")
  @redis.del("#{event_id}:last_acknowledgement_notification")
end

def set_ok_state(entity = 'clientx-dvmh-app-01', check = 'ping')
  event_id = entity + ":" + check
  @redis.hset(event_id, 'state', 'ok')
  @redis.hset(event_id, 'last_change', (Time.now.to_i - (60*60*24)))
  @redis.zrem('failed_checks', event_id)
  @redis.zrem('failed_checks:client:clientx', event_id)
end

def set_failure_state(entity = 'clientx-dvmh-app-01', check = 'ping')
  event_id = entity + ":" + check
  @redis.hset(event_id, 'state', 'critical')
  @redis.hset(event_id, 'last_change', (Time.now.to_i - (60*60*24)))
  @redis.zadd('failed_checks', (Time.now.to_i - (60*60*24)), event_id)
  @redis.zadd('failed_checks:client:clientx', (Time.now.to_i - (60*60*24)), event_id)
end

def submit_ok(entity = 'clientx-dvmh-app-01', check = 'ping')
  event = {
    'type'    => 'service',
    'state'   => 'ok',
    'summary' => '0% packet loss',
    'entity'  => entity,
    'check'   => check,
  }
  submit_event(event)
end

def submit_critical(entity = 'clientx-dvmh-app-01', check = 'ping')
  event = {
    'type'    => 'service',
    'state'   => 'critical',
    'summary' => '100% packet loss',
    'entity'  => entity,
    'check'   => check,
  }
  submit_event(event)
end

def submit_acknowledgement(entity = 'clientx-dvmh-app-01', check = 'ping')
  event = {
    'type'    => 'action',
    'state'   => 'acknowledgement',
    'summary' => "I'll have this fixed in a jiffy, saw the same thing yesterday",
    'entity'  => entity,
    'check'   => check,
  }
  submit_event(event)
end

def process_events
  @app.process_events
end

Given /^check x is in an ok state$/ do
  remove_unscheduled_maintenance
  remove_scheduled_maintenance
  remove_notifications
  set_ok_state
end

Given /^check x is in a failure state$/ do
  remove_unscheduled_maintenance
  remove_scheduled_maintenance
  remove_notifications
  set_failure_state
end

Given /^check x is in scheduled maintenance$/ do
  remove_unscheduled_maintenance
  set_scheduled_maintenance
end

Given /^check x is in unscheduled maintenance$/ do
  remove_scheduled_maintenance
  set_failure_state
  submit_acknowledgement
  process_events
end

When /^an ok event is received for check x$/ do
  submit_ok
  process_events
end

Then /^a notification should not be generated for check x$/ do
  $notification.should =~ /Not sending notifications for event/
end

Then /^a notification should be generated for check x$/ do
  process_events
  $notification.should =~ /Sending notifications for event/
end

When /^a failure event is received for check x$/ do
  submit_critical
  process_events
end

When /^an acknowledgement is received for check x$/ do
  submit_acknowledgement
  process_events
end

When /^an acknowledgement event is received for check x$/ do
  submit_acknowledgement
  process_events
end

Then /^show me the notification$/ do
  puts $notification
end

