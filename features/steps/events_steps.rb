#!/usr/bin/env ruby
require 'redis'
require 'json'

def submit_event(event)
  @redis = Redis.new
  @redis.rpush 'events', event.to_json
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

def remove_unscheduled_maintenance(host = 'clientx-dvmh-app-01', service = 'ping')

end

def process_events
  @output = `tmp/process_events`
end


Given /^service x is in an ok state$/ do
  remove_unscheduled_maintenance
  submit_ok
end

When /^an ok event is received for service x$/ do
  pending # express the regexp above with the code you wish you had
end

Then /^a notification should not be generated for service x$/ do
  # read the rest of the scenario log file for "Not sending notifications for event xxx;xxx"
  pending # express the regexp above with the code you wish you had
end

When /^a failure event is received for service x$/ do
  pending # express the regexp above with the code you wish you had
end

When /^(\d+) second.* passes$/ do |arg1|
  pending # express the regexp above with the code you wish you had
end

When /^(\d+) minute.* passes$/ do |arg1|
  pending # express the regexp above with the code you wish you had
end

Then /^a notification should be generated for service x$/ do
  # read the rest of the scenario log file for "Sending notifications for event xxx;xxx"
  pending # express the regexp above with the code you wish you had
end

Given /^service x is in scheduled maintenance$/ do
  pending # express the regexp above with the code you wish you had
end

Given /^service x is in unscheduled maintenance$/ do
  pending # express the regexp above with the code you wish you had
end

When /^an acknowledgement is received for service x$/ do
  pending # express the regexp above with the code you wish you had
end

Given /^service x is in a failure state$/ do
  pending # express the regexp above with the code you wish you had
end

When /^an acknowledgement event is received for service x$/ do
  pending # express the regexp above with the code you wish you had
end

