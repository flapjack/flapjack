#!/usr/bin/env ruby

def drain_events
  Flapjack::Data::Event.foreach_on_queue('events') do |event|
    @processor.send(:process_event, event)
  end
  drain_notifications
end

def drain_notifications
  return unless @notifier
  Flapjack::Data::Notification.foreach_on_queue('notifications') do |notification|
    @notifier.send(:process_notification, notification)
  end
end

def submit_event(event)
  Flapjack.redis.rpush 'events', event.to_json
end

def set_scheduled_maintenance(entity, check, duration = 60*60*2)
  entity_check = Flapjack::Data::EntityCheck.for_entity_name(entity, check)
  t = Time.now.to_i
  entity_check.create_scheduled_maintenance(t, duration, :summary => "upgrading everything")
  Flapjack.redis.setex("#{entity}:#{check}:scheduled_maintenance", duration, t)
end

def remove_scheduled_maintenance(entity, check)
  entity_check = Flapjack::Data::EntityCheck.for_entity_name(entity, check)
  sm = entity_check.maintenances(nil, nil, :scheduled => true)
  sm.each do |m|
    entity_check.end_scheduled_maintenance(m[:start_time])
  end
end

def remove_unscheduled_maintenance(entity, check)
  # end any unscheduled downtime
  event_id = entity + ":" + check
  if (um_start = Flapjack.redis.get("#{event_id}:unscheduled_maintenance"))
    Flapjack.redis.del("#{event_id}:unscheduled_maintenance")
    duration = Time.now.to_i - um_start.to_i
    Flapjack.redis.zadd("#{event_id}:unscheduled_maintenances", duration, um_start)
  end
end

def remove_notifications(entity, check)
  event_id = entity + ":" + check
  Flapjack.redis.del("#{event_id}:last_problem_notification")
  Flapjack.redis.del("#{event_id}:last_recovery_notification")
  Flapjack.redis.del("#{event_id}:last_acknowledgement_notification")
end

def set_ok_state(entity, check)
  entity_check = Flapjack::Data::EntityCheck.for_entity_name(entity, check)
  entity_check.update_state(Flapjack::Data::EntityCheck::STATE_OK,
    :timestamp => (Time.now.to_i - (60*60*24)))
end

def set_critical_state(entity, check)
  entity_check = Flapjack::Data::EntityCheck.for_entity_name(entity, check)
  entity_check.update_state(Flapjack::Data::EntityCheck::STATE_CRITICAL,
    :timestamp => (Time.now.to_i - (60*60*24)))
end

def set_warning_state(entity, check)
  entity_check = Flapjack::Data::EntityCheck.for_entity_name(entity, check)
  entity_check.update_state(Flapjack::Data::EntityCheck::STATE_WARNING,
    :timestamp => (Time.now.to_i - (60*60*24)))
end

def end_unscheduled_maintenance(entity, check)
  entity_check = Flapjack::Data::EntityCheck.for_entity_name(entity, check)
  entity_check.end_unscheduled_maintenance(Time.now.to_i)
end

def submit_ok(entity, check)
  event = {
    'type'    => 'service',
    'state'   => 'ok',
    'summary' => '0% packet loss',
    'entity'  => entity,
    'check'   => check,
    'client'  => 'clientx'
  }
  submit_event(event)
end

def submit_warning(entity, check)
  event = {
    'type'    => 'service',
    'state'   => 'warning',
    'summary' => '25% packet loss',
    'entity'  => entity,
    'check'   => check,
    'client'  => 'clientx'
  }
  submit_event(event)
end

def submit_critical(entity, check)
  event = {
    'type'    => 'service',
    'state'   => 'critical',
    'summary' => '100% packet loss',
    'entity'  => entity,
    'check'   => check,
    'client'  => 'clientx'
  }
  submit_event(event)
end

def submit_unknown(entity, check)
  event = {
    'type'    => 'service',
    'state'   => 'unknown',
    'summary' => 'check execution error',
    'entity'  => entity,
    'check'   => check,
    'client'  => 'clientx'
  }
  submit_event(event)
end

def submit_acknowledgement(entity, check)
  event = {
    'type'               => 'action',
    'state'              => 'acknowledgement',
    'summary'            => "I'll have this fixed in a jiffy, saw the same thing yesterday",
    'entity'             => entity,
    'check'              => check,
    'client'             => 'clientx',
  }
  submit_event(event)
end

def submit_test(entity, check)
  event = {
    'type'               => 'action',
    'state'              => 'test_notifications',
    'summary'            => "test notification for all contacts interested in #{entity}",
    'entity'             => entity,
    'check'              => check,
    'client'             => 'clientx',
  }
  submit_event(event)
end

def icecube_schedule_to_time_restriction(sched, time_zone)
  tr = sched.to_hash
  tr[:start_time] = time_zone.utc_to_local(tr[:start_date][:time]).strftime "%Y-%m-%d %H:%M:%S"
  tr[:end_time]   = time_zone.utc_to_local(tr[:end_time][:time]).strftime "%Y-%m-%d %H:%M:%S"

  # rewrite IceCube::WeeklyRule to Weekly, etc
  tr[:rrules].each {|rrule|
    rrule[:rule_type] = /^.*\:\:(.*)Rule$/.match(rrule[:rule_type])[1]
  }

  tr
end

Given /^an entity '([\w\.\-]+)' exists$/ do |entity|
  Flapjack::Data::Entity.add({'id'       => '5000',
                              'name'     => entity})
end

Given /^the check is check '(.*)' on entity '([\w\.\-]+)'$/ do |check, entity|
  @check  = check
  @entity = entity
end

Given /^(?:the check|check '([\w\.\-]+)' for entity '([\w\.\-]+)') has no state$/ do |check, entity|
  check  ||= @check
  entity ||= @entity
  remove_unscheduled_maintenance(entity, check)
  remove_scheduled_maintenance(entity, check)
  remove_notifications(entity, check)
  Flapjack.redis.hdel("check:#{@key}", 'state')
end

Given /^(?:the check|check '([\w\.\-]+)' for entity '([\w\.\-]+)') is in an ok state$/ do |check, entity|
  check  ||= @check
  entity ||= @entity
  remove_unscheduled_maintenance(entity, check)
  remove_scheduled_maintenance(entity, check)
  remove_notifications(entity, check)
  set_ok_state(entity, check)
end

Given /^(?:the check|check '([\w\.\-]+)' for entity '([\w\.\-]+)') is in a critical state$/ do |check, entity|
  check  ||= @check
  entity ||= @entity
  remove_unscheduled_maintenance(entity, check)
  remove_scheduled_maintenance(entity, check)
  remove_notifications(entity, check)
  set_critical_state(entity, check)
end

Given /^(?:the check|check '([\w\.\-]+)' for entity '([\w\.\-]+)') is in scheduled maintenance(?: for (.+))?$/ do |check, entity, duration|
  check  ||= @check
  entity ||= @entity
  durn = duration ? ChronicDuration.parse(duration) : 60*60*2
  remove_unscheduled_maintenance(entity, check)
  set_scheduled_maintenance(entity, check, durn)
end

# TODO set the state directly rather than submit & drain
Given /^(?:the check|check '([\w\.\-]+)' for entity '([\w\.\-]+)') is in unscheduled maintenance$/ do |check, entity|
  check  ||= @check
  entity ||= @entity
  remove_scheduled_maintenance(entity, check)
  set_critical_state(entity, check)
  submit_acknowledgement(entity, check)
  drain_events  # TODO these should only be in When clauses
end

When /^an ok event is received(?: for check '([\w\.\-]+)' on entity '([\w\.\-]+)')?$/ do |check, entity|
  check  ||= @check
  entity ||= @entity
  submit_ok(entity, check)
  drain_events
end

When /^a failure event is received(?: for check '([\w\.\-]+)' on entity '([\w\.\-]+)')?$/ do |check, entity|
  check  ||= @check
  entity ||= @entity
  submit_critical(entity, check)
  drain_events
end

When /^a critical event is received(?: for check '([\w\.\-]+)' on entity '([\w\.\-]+)')?$/ do |check, entity|
  check  ||= @check
  entity ||= @entity
  submit_critical(entity, check)
  drain_events
end

When /^a warning event is received(?: for check '([\w\.\-]+)' on entity '([\w\.\-]+)')?$/ do |check, entity|
  check  ||= @check
  entity ||= @entity
  submit_warning(entity, check)
  drain_events
end

When /^an unknown event is received(?: for check '([\w\.\-]+)' on entity '([\w\.\-]+)')?$/ do |check, entity|
  check  ||= @check
  entity ||= @entity
  submit_unknown(entity, check)
  drain_events
end

When /^an acknowledgement .*is received(?: for check '([\w\.\-]+)' on entity '([\w\.\-]+)')?$/ do |check, entity|
  check  ||= @check
  entity ||= @entity
  submit_acknowledgement(entity, check)
  drain_events
end

When /^a test .*is received(?: for check '([\w\.\-]+)' on entity '([\w\.\-]+)')?$/ do |check, entity|
  check  ||= @check
  entity ||= @entity
  submit_test(entity, check)
  drain_events
end

When /^the unscheduled maintenance is ended(?: for check '([\w\.\-]+)' on entity '([\w\.\-]+)')?$/ do |check, entity|
  check  ||= @check
  entity ||= @entity
  end_unscheduled_maintenance(entity, check)
end

# TODO logging is a side-effect, should test for notification generation itself
Then /^a notification should not be generated(?: for check '([\w\.\-]+)' on entity '([\w\.\-]+)')?$/ do |check, entity|
  check  ||= @check
  entity ||= @entity
  message = @logger.messages.find_all {|m| m =~ /enerating notification for event #{entity}:#{check}/ }.last
  found = message ? message.match(/Not generating notification/) : false
  found.should be_true
end

Then /^a notification should be generated(?: for check '([\w\.\-]+)' on entity '([\w\.\-]+)')?$/ do |check, entity|
  check  ||= @check
  entity ||= @entity
  message = @logger.messages.find_all {|m| m =~ /enerating notification for event #{entity}:#{check}/ }.last
  found = message ? message.match(/Generating notification/) : false
  found.should be_true
end

Then /^(un)?scheduled maintenance should be generated(?: for check '([\w\.\-]+)' on entity '([\w\.\-]+)')?$/ do |unsched, check, entity|
  check  ||= @check
  entity ||= @entity
  Flapjack.redis.get("#{entity}:#{check}:#{unsched || ''}scheduled_maintenance").should_not be_nil
end

Then /^show me the (\w+ )*log$/ do |adjective|
  puts "the #{adjective}log:"
  puts @logger.messages.join("\n")
end

Then /^dump notification rules for user (\d+)$/ do |contact|
  rule_ids = Flapjack.redis.smembers("contact_notification_rules:#{contact}")
  puts "There #{(rule_ids.length == 1) ? 'is' : 'are'} #{rule_ids.length} notification rule#{(rule_ids.length == 1) ? '' : 's'} for user #{contact}:"
  rule_ids.each {|rule_id|
    rule = Flapjack::Data::NotificationRule.find_by_id(rule_id)
    puts rule.to_json
  }
end

# added for notification rules:
Given /^the following entities exist:$/ do |entities|
  entities.hashes.each do |entity|
    contacts = entity['contacts'].split(',')
    contacts.map! do |contact|
      contact.strip
    end
    Flapjack::Data::Entity.add({'id'       => entity['id'],
                                'name'     => entity['name'],
                                'contacts' => contacts})
  end
end

Given /^the following users exist:$/ do |contacts|
  contacts.hashes.each do |contact|
    media = {}
    media['email'] = { 'address' => contact['email'] }
    media['sms']   = { 'address' => contact['sms'] }
    Flapjack::Data::Contact.add({'id'         => contact['id'],
                                 'first_name' => contact['first_name'],
                                 'last_name'  => contact['last_name'],
                                 'email'      => contact['email'],
                                 'media'      => media}).timezone = contact['timezone']
  end
end

Given /^user (\d+) has the following notification intervals:$/ do |contact_id, intervals|
  contact = Flapjack::Data::Contact.find_by_id(contact_id)
  intervals.hashes.each do |interval|
    contact.set_interval_for_media('email', interval['email'].to_i * 60)
    contact.set_interval_for_media('sms',   interval['sms'].to_i * 60)
  end
end

Given /^user (\d+) has the following notification rollup thresholds:$/ do |contact_id, rollup_thresholds|
  contact = Flapjack::Data::Contact.find_by_id(contact_id)
  rollup_thresholds.hashes.each do |rollup_threshold|
    contact.set_rollup_threshold_for_media('email', rollup_threshold['email'].to_i)
    contact.set_rollup_threshold_for_media('sms',   rollup_threshold['sms'].to_i)
  end
end

Given /^user (\d+) has the following notification rules:$/ do |contact_id, rules|
  contact = Flapjack::Data::Contact.find_by_id(contact_id)
  timezone = contact.timezone

  # delete any autogenerated rules, and do it using redis directly so no new
  # ones will be created
  contact.notification_rules.each do |nr|
    Flapjack.redis.srem("contact_notification_rules:#{contact_id}", nr.id)
    Flapjack.redis.del("notification_rule:#{nr.id}")
  end
  rules.hashes.each do |rule|
    entities           = rule['entities']           ? rule['entities'].split(',').map       { |x| x.strip } : []
    tags               = rule['tags']               ? rule['tags'].split(',').map           { |x| x.strip } : []
    unknown_media      = rule['unknown_media']      ? rule['unknown_media'].split(',').map  { |x| x.strip } : []
    warning_media      = rule['warning_media']      ? rule['warning_media'].split(',').map  { |x| x.strip } : []
    critical_media     = rule['critical_media']     ? rule['critical_media'].split(',').map { |x| x.strip } : []
    unknown_blackhole  = rule['unknown_blackhole']  ? (rule['unknown_blackhole'].downcase == 'true')  : false
    warning_blackhole  = rule['warning_blackhole']  ? (rule['warning_blackhole'].downcase == 'true')  : false
    critical_blackhole = rule['critical_blackhole'] ? (rule['critical_blackhole'].downcase == 'true') : false
    time_restrictions  = rule['time_restrictions']  ? rule['time_restrictions'].split(',').map { |x|
      x.strip
    }.inject([]) { |memo, time_restriction|
      case time_restriction
      when '8-18 weekdays'
        weekdays_8_18 = IceCube::Schedule.new(timezone.local(2013,2,1,8,0,0), :duration => 60 * 60 * 10)
        weekdays_8_18.add_recurrence_rule(IceCube::Rule.weekly.day(:monday, :tuesday, :wednesday, :thursday, :friday))
        memo << icecube_schedule_to_time_restriction(weekdays_8_18, timezone)
      end
    } : []
    rule_data = {:contact_id         => contact_id,
                 :entities           => entities,
                 :tags               => tags,
                 :unknown_media      => unknown_media,
                 :warning_media      => warning_media,
                 :critical_media     => critical_media,
                 :unknown_blackhole  => unknown_blackhole,
                 :warning_blackhole  => warning_blackhole,
                 :critical_blackhole => critical_blackhole,
                 :time_restrictions  => time_restrictions}
    created_rule = Flapjack::Data::NotificationRule.add(rule_data)
    unless created_rule.is_a?(Flapjack::Data::NotificationRule)
      raise "Error creating notification rule with data: #{rule_data}, errors: #{created_rule.join(', ')}"
    end
  end
end

Then /^all alert dropping keys for user (\d+) should have expired$/ do |contact_id|
  Flapjack.redis.keys("drop_alerts_for_contact:#{contact_id}*").should be_empty
end

Then /^(\w+) (\w+) alert(?:s)?(?: of)?(?: type (\w+))?(?: and)?(?: rollup (\w+))? should be queued for (.*)$/ do |num_queued, media, notification_type, rollup, address|
  check  = check  ? check  : @check
  entity = entity ? entity : @entity
  case num_queued
  when 'no'
    num_queued = 0
  end
  queue = redis_peek("#{media}_notifications", 0, 30)
  queue.find_all {|n|
    type_ok = notification_type ? ( n['notification_type'] == notification_type ) : true
    rollup_ok = true
    if rollup
      if rollup == 'none'
        rollup_ok = n['rollup'].nil?
      else
        rollup_ok = n['rollup'] == rollup
      end
    end
    type_ok && rollup_ok && ( n['address'] == address )
  }.length.should == num_queued.to_i
end
