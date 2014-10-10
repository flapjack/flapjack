#!/usr/bin/env ruby

def drain_events
  @processor.send(:foreach_on_queue, 'events') do |event|
    @processor.send(:process_event, event)
    @last_event_count = event.counter
  end
  drain_notifications
end

def drain_notifications
  return unless @notifier
  @notifier.instance_variable_get('@queue').send(:foreach) do |notification|
    @notifier.send(:process_notification, notification)
  end
end

def submit_event(event)
  Flapjack.redis.rpush('events', Flapjack.dump_json(event))
end

def set_scheduled_maintenance(entity_name, check_name, duration)
  check = Flapjack::Data::Check.intersect(:name => "#{entity_name}:#{check_name}").all.first
  expect(check).not_to be_nil

  t = Time.now
  sched_maint = Flapjack::Data::ScheduledMaintenance.new(:start_time => t,
    :end_time => Time.at(t.to_i + duration), :summary => 'upgrading everything')
  expect(sched_maint.save).to be true
  check.add_scheduled_maintenance(sched_maint)
end

def remove_scheduled_maintenance(entity_name, check_name)
  check = Flapjack::Data::Check.intersect(:name => "#{entity_name}:#{check_name}").all.first
  expect(check).not_to be_nil

  t = Time.now
  sched_maints = check.scheduled_maintenances_by_start.all
  sched_maints.each do |sm|
    check.end_scheduled_maintenance(sm, t)
    sched_maint.destroy
  end
end

def set_unscheduled_maintenance(entity_name, check_name, duration)
  check = Flapjack::Data::Check.intersect(:name => "#{entity_name}:#{check_name}").all.first
  expect(check).not_to be_nil

  t = Time.now
  unsched_maint = Flapjack::Data::UnscheduledMaintenance.new(:start_time => t,
    :end_time => Time.at(t.to_i + duration), :summary => 'fixing now')
  expect(unsched_maint.save).to be true
  check.set_unscheduled_maintenance(unsched_maint)
end

def clear_unscheduled_maintenance(entity_name, check_name)
  check = Flapjack::Data::Check.intersect(:name => "#{entity_name}:#{check_name}").all.first
  expect(check).not_to be_nil

  check.clear_unscheduled_maintenance(Time.now)
end

def set_state(entity_name, check_name, state, last_update)
  check = Flapjack::Data::Check.intersect(:name => "#{entity_name}:#{check_name}").all.first
  expect(check).not_to be_nil

  check.state = state
  check.last_update = last_update
  check.save
end

def submit_ok(entity_name, check_name)
  event = {
    'type'    => 'service',
    'state'   => 'ok',
    'summary' => '0% packet loss',
    'entity'  => entity_name,
    'check'   => check_name,
  }
  submit_event(event)
end

def submit_warning(entity_name, check_name)
  event = {
    'type'    => 'service',
    'state'   => 'warning',
    'summary' => '25% packet loss',
    'entity'  => entity_name,
    'check'   => check_name,
  }
  submit_event(event)
end

def submit_critical(entity_name, check_name)
  event = {
    'type'    => 'service',
    'state'   => 'critical',
    'summary' => '100% packet loss',
    'entity'  => entity_name,
    'check'   => check_name,
  }
  submit_event(event)
end

def submit_unknown(entity_name, check_name)
  event = {
    'type'    => 'service',
    'state'   => 'unknown',
    'summary' => 'check execution error',
    'entity'  => entity_name,
    'check'   => check_name,
  }
  submit_event(event)
end

def submit_acknowledgement(entity_name, check_name)
  event = {
    'type'    => 'action',
    'state'   => 'acknowledgement',
    'summary' => "I'll have this fixed in a jiffy, saw the same thing yesterday",
    'entity'  => entity_name,
    'check'   => check_name,
  }
  submit_event(event)
end

def submit_test(entity_name, check_name)
  event = {
    'type'    => 'action',
    'state'   => 'test_notifications',
    'summary' => "test notification for all contacts interested in #{entity_name}",
    'entity'  => entity_name,
    'check'   => check_name,
  }
  submit_event(event)
end

def icecube_schedule_to_time_restriction(sched, time_zone)
  tr = sched.to_hash
  tr[:start_time] = {:time => time_zone.utc_to_local(tr[:start_time][:time]).strftime("%Y-%m-%d %H:%M:%S"), :zone => time_zone}
  tr[:end_time]   = {:time => time_zone.utc_to_local(tr[:end_time][:time]).strftime("%Y-%m-%d %H:%M:%S"), :zone => time_zone}

  # rewrite IceCube::WeeklyRule to Weekly, etc
  tr[:rrules].each {|rrule|
    rrule[:rule_type] = /^.*\:\:(.*)Rule$/.match(rrule[:rule_type])[1]
  }

  stringify(tr)
end

def stringify(obj)
  return obj.inject({}){|memo,(k,v)| memo[k.to_s] =  stringify(v); memo} if obj.is_a?(Hash)
  return obj.inject([]){|memo,v    | memo         << stringify(v); memo} if obj.is_a?(Array)
  obj
end

Given /^the check is check '(.*)' on entity '([\w\.\-]+)'$/ do |check_name, entity_name|
  check = Flapjack::Data::Check.intersect(:name => "#{entity_name}:#{check_name}").all.first
  if check.nil?
    check = Flapjack::Data::Check.new(:name => "#{entity_name}:#{check_name}")
    expect(check.save).to be true
  end

  @check_name  = check_name
  @entity_name = entity_name
end

Given /^(?:the check|check '([\w\.\-]+)' for entity '([\w\.\-]+)') has no state$/ do |check_name, entity_name|
  check_name  ||= @check_name
  entity_name ||= @entity_name
  clear_unscheduled_maintenance(entity_name, check_name)
  remove_scheduled_maintenance(entity_name, check_name)
end

Given /^(?:the check|check '([\w\.\-]+)' for entity '([\w\.\-]+)') is in an? (ok|critical) state$/ do |check_name, entity_name, state|
  check_name  ||= @check_name
  entity_name ||= @entity_name
  clear_unscheduled_maintenance(entity_name, check_name)
  set_state(entity_name, check_name, state, Time.now.to_i - (6 * 60 *60))
  remove_scheduled_maintenance(entity_name, check_name)
end

Given /^(?:the check|check '([\w\.\-]+)' for entity '([\w\.\-]+)') is in scheduled maintenance(?: for (.+))?$/ do |check_name, entity_name, duration|
  check_name  ||= @check_name
  entity_name ||= @entity_name
  durn = duration ? ChronicDuration.parse(duration) : (6 * 60 *60)
  clear_unscheduled_maintenance(entity_name, check_name)
  set_scheduled_maintenance(entity_name, check_name, durn)
end

Given /^(?:the check|check '([\w\.\-]+)' for entity '([\w\.\-]+)') is in unscheduled maintenance$/ do |check_name, entity_name|
  check_name  ||= @check_name
  entity_name ||= @entity_name
  set_unscheduled_maintenance(entity_name, check_name, 60*60*2)
  set_state(entity_name, check_name, 'critical', Time.now.to_i - (6 * 60 *60))
  remove_scheduled_maintenance(entity_name, check_name)
end

When /^an ok event is received(?: for check '([\w\.\-]+)' on entity '([\w\.\-]+)')?$/ do |check_name, entity_name|
  check_name  ||= @check_name
  entity_name ||= @entity_name
  submit_ok(entity_name, check_name)
  drain_events
end

When /^a failure event is received(?: for check '([\w\.\-]+)' on entity '([\w\.\-]+)')?$/ do |check_name, entity_name|
  check_name  ||= @check_name
  entity_name ||= @entity_name
  submit_critical(entity_name, check_name)
  drain_events
end

When /^a critical event is received(?: for check '([\w\.\-]+)' on entity '([\w\.\-]+)')?$/ do |check_name, entity_name|
  check_name  ||= @check_name
  entity_name ||= @entity_name
  submit_critical(entity_name, check_name)
  drain_events
end

When /^a warning event is received(?: for check '([\w\.\-]+)' on entity '([\w\.\-]+)')?$/ do |check_name, entity_name|
  check_name  ||= @check_name
  entity_name ||= @entity_name
  submit_warning(entity_name, check_name)
  drain_events
end

When /^an unknown event is received(?: for check '([\w\.\-]+)' on entity '([\w\.\-]+)')?$/ do |check_name, entity_name|
  check_name  ||= @check_name
  entity_name ||= @entity_name
  submit_unknown(entity_name, check_name)
  drain_events
end

When /^an acknowledgement .*is received(?: for check '([\w\.\-]+)' on entity '([\w\.\-]+)')?$/ do |check_name, entity_name|
  check_name  ||= @check_name
  entity_name ||= @entity_name
  submit_acknowledgement(entity_name, check_name)
  drain_events
end

When /^a test .*is received(?: for check '([\w\.\-]+)' on entity '([\w\.\-]+)')?$/ do |check_name, entity_name|
  check_name  ||= @check_name
  entity_name ||= @entity_name
  submit_test(entity_name, check_name)
  drain_events
end

When /^the unscheduled maintenance is ended(?: for check '([\w\.\-]+)' on entity '([\w\.\-]+)')?$/ do |check_name, entity_name|
  check_name  ||= @check_name
  entity_name ||= @entity_name
  clear_unscheduled_maintenance(entity_name, check_name)
end

Then /^a notification should not be generated(?: for check '([\w\.\-]+)' on entity '([\w\.\-]+)')?$/ do |check_name, entity_name|
  check_name  ||= @check_name
  entity_name ||= @entity_name

  check = Flapjack::Data::Check.intersect(:name => "#{entity_name}:#{check_name}").all.first
  expect(check).not_to be_nil

  if last_notification = check.last_notification
    puts @logger.messages.join("\n\n") if last_notification.last_notification_count == @last_event_count
    expect(last_notification.last_notification_count).not_to eq(@last_event_count)
  end
end

Then /^a notification should be generated(?: for check '([\w\.\-]+)' on entity '([\w\.\-]+)')?$/ do |check_name, entity_name|
  check_name  ||= @check_name
  entity_name ||= @entity_name

  check = Flapjack::Data::Check.intersect(:name => "#{entity_name}:#{check_name}").all.first
  expect(check).not_to be_nil

  last_notification = check.last_notification
  expect(last_notification).not_to be_nil
  puts @logger.messages.join("\n\n") if last_notification.last_notification_count != @last_event_count
  expect(last_notification.last_notification_count).to eq(@last_event_count)
end

Then /^(un)?scheduled maintenance should be generated(?: for check '([\w\.\-]+)' on entity '([\w\.\-]+)')?$/ do |unsched, check_name, entity_name|
  check_name  ||= @check_name
  entity_name ||= @entity_name

  check = Flapjack::Data::Check.intersect(:name => "#{entity_name}:#{check_name}").all.first
  expect(check).not_to be_nil

  expect(check).to (unsched ? be_in_unscheduled_maintenance : be_in_scheduled_maintenance)
end

Then /^show me the (\w+ )*log$/ do |adjective|
  puts "the #{adjective}log:"
  puts @logger.messages.join("\n")
end

Then /^dump notification rules for user (\S+)$/ do |contact|
  rule_ids = Flapjack.redis.smembers("contact_notification_rules:#{contact}")
  puts "There #{(rule_ids.length == 1) ? 'is' : 'are'} #{rule_ids.length} notification rule#{(rule_ids.length == 1) ? '' : 's'} for user #{contact}:"
  rule_ids.each {|rule_id|
    rule = Flapjack::Data::Notificationule.find_by_id(rule_id)
    puts Flapjack.dump_json(rule)
  }
end

Then /^all alert dropping keys for user (\S+) should have expired$/ do |contact_id|
  expect(Flapjack.redis.keys("drop_alerts_for_contact:#{contact_id}*")).to be_empty
end

Then /^(\w+) (\w+) alert(?:s)?(?: of)?(?: type (\w+))?(?: and)?(?: rollup (\w+))? should be queued for (.*)$/ do |num_queued, media, notification_type, rollup, address|
  case num_queued
  when 'no'
    num_queued = 0
  end
  queued = redis_peek("#{media}_notifications", Flapjack::Data::Alert, 0, 30)
  queued_length = queued.find_all {|alert|
    type_ok = notification_type ? ( alert.notification_type == notification_type ) : true
    rollup_ok = true
    if rollup
      if rollup == 'none'
        rollup_ok = alert.rollup.nil?
      else
        rollup_ok = (alert.rollup == rollup)
      end
    end
    type_ok && rollup_ok && (alert.medium.address == address)
  }.length
  expect(queued_length).to eq(num_queued.to_i)
end

When(/^user with id '(\S+)' removes rule with id '(\S+)'$/) do |contact_id, rule_id|
  rule = Flapjack::Data::Rule.find_by_id(rule_id)
  expect(rule).not_to be_nil

  rule.destroy
end
