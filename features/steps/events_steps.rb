#!/usr/bin/env ruby

def drain_events
  Flapjack::Data::Event.foreach_on_queue('events') do |event|
    @processor.send(:process_event, event)
    @last_event_count = event.counter
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

def set_scheduled_maintenance(entity, check, duration)
  entity_check = Flapjack::Data::Check.intersect(:entity_name => entity, :name => check).all.first

  t = Time.now
  sched_maint = Flapjack::Data::ScheduledMaintenance.new(:start_time => t,
    :end_time => Time.at(t.to_i + duration), :summary => 'upgrading everything')
  sched_maint.save.should be_true
  entity_check.add_scheduled_maintenance(sched_maint)
end

def remove_scheduled_maintenance(entity, check)
  entity_check = Flapjack::Data::Check.intersect(:entity_name => entity, :name => check).all.first

  t = Time.now
  sched_maints = entity_check.scheduled_maintenances_by_start.all
  sched_maints.each do |sm|
    entity_check.end_scheduled_maintenance(sm, t)
    sched_maint.destroy
  end
end

def set_unscheduled_maintenance(entity, check, duration)
  entity_check = Flapjack::Data::Check.intersect(:entity_name => entity, :name => check).all.first

  t = Time.now
  unsched_maint = Flapjack::Data::UnscheduledMaintenance.new(:start_time => t,
    :end_time => Time.at(t.to_i + duration), :summary => 'fixing now')
  unsched_maint.save.should be_true
  entity_check.set_unscheduled_maintenance(unsched_maint)
end

def clear_unscheduled_maintenance(entity, check)
  entity_check = Flapjack::Data::Check.intersect(:entity_name => entity, :name => check).all.first
  entity_check.clear_unscheduled_maintenance(Time.now)
end

# def remove_notifications(entity, check)
#   event_id = entity + ":" + check
#   Flapjack.redis.del("#{event_id}:last_problem_notification")
#   Flapjack.redis.del("#{event_id}:last_recovery_notification")
#   Flapjack.redis.del("#{event_id}:last_acknowledgement_notification")
# end

def set_state(entity, check, state, last_update)
  entity_check = Flapjack::Data::Check.intersect(:entity_name => entity, :name => check).all.first
  entity_check.state = state
  entity_check.last_update = last_update
  entity_check.save
end

def submit_ok(entity, check)
  event = {
    'type'    => 'service',
    'state'   => 'ok',
    'summary' => '0% packet loss',
    'entity'  => entity,
    'check'   => check,
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

  stringify(tr)
end

def stringify(obj)
  return obj.inject({}){|memo,(k,v)| memo[k.to_s] =  stringify(v); memo} if obj.is_a?(Hash)
  return obj.inject([]){|memo,v    | memo         << stringify(v); memo} if obj.is_a?(Array)
  obj
end

Given /^an entity '([\w\.\-]+)' exists$/ do |entity_name|
  entity = Flapjack::Data::Entity.intersect(:name => entity_name).all.first
  if entity.nil?
    entity = Flapjack::Data::Entity.new(:id   => '5000',
                                         :name => entity_name)
    entity.save
  end
end

Given /^the check is check '(.*)' on entity '([\w\.\-]+)'$/ do |check_name, entity_name|
  entity = Flapjack::Data::Entity.intersect(:name => entity_name).all.first
  entity.should_not be_nil

  entity_check = Flapjack::Data::Check.intersect(:entity_name => entity_name, :name => check_name).all.first
  if entity_check.nil?
    entity_check = Flapjack::Data::Check.new(:entity_name => entity_name, :name => check_name)
    entity_check.save.should_not be_false
  end
  entity.checks << entity_check

  @check  = check_name
  @entity = entity_name
end

Given /^(?:the check|check '([\w\.\-]+)' for entity '([\w\.\-]+)') has no state$/ do |check, entity|
  check  ||= @check
  entity ||= @entity
  clear_unscheduled_maintenance(entity, check)
  remove_scheduled_maintenance(entity, check)
  # remove_notifications(entity, check)
  # Flapjack.redis.hdel("check:#{@key}", 'state')
end

Given /^(?:the check|check '([\w\.\-]+)' for entity '([\w\.\-]+)') is in an? (ok|critical) state$/ do |check, entity, state|
  check  ||= @check
  entity ||= @entity
  clear_unscheduled_maintenance(entity, check)
  set_state(entity, check, state, Time.now.to_i - (6 * 60 *60))
  remove_scheduled_maintenance(entity, check)
end

Given /^(?:the check|check '([\w\.\-]+)' for entity '([\w\.\-]+)') is in scheduled maintenance(?: for (.+))?$/ do |check, entity, duration|
  check  ||= @check
  entity ||= @entity
  durn = duration ? ChronicDuration.parse(duration) : (6 * 60 *60)
  clear_unscheduled_maintenance(entity, check)
  set_scheduled_maintenance(entity, check, durn)
end

Given /^(?:the check|check '([\w\.\-]+)' for entity '([\w\.\-]+)') is in unscheduled maintenance$/ do |check, entity|
  check  ||= @check
  entity ||= @entity
  set_unscheduled_maintenance(entity, check, 60*60*2)
  set_state(entity, check, 'critical', Time.now.to_i - (6 * 60 *60))
  remove_scheduled_maintenance(entity, check)
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
  clear_unscheduled_maintenance(entity, check)
end

Then /^a notification should not be generated(?: for check '([\w\.\-]+)' on entity '([\w\.\-]+)')?$/ do |check, entity|
  check  ||= @check
  entity ||= @entity

  entity_check = Flapjack::Data::Check.intersect(:entity_name => entity, :name => check).all.first
  entity_check.should_not be_nil

  if last_notification = entity_check.last_notification
    puts @logger.messages.join("\n\n") if last_notification.last_notification_count == @last_event_count
    last_notification.last_notification_count.should_not == @last_event_count
  end
end

Then /^a notification should be generated(?: for check '([\w\.\-]+)' on entity '([\w\.\-]+)')?$/ do |check, entity|
  check  ||= @check
  entity ||= @entity

  entity_check = Flapjack::Data::Check.intersect(:entity_name => entity, :name => check).all.first
  entity_check.should_not be_nil

  last_notification = entity_check.last_notification
  last_notification.should_not be_nil
  puts @logger.messages.join("\n\n") if last_notification.last_notification_count != @last_event_count
  last_notification.last_notification_count.should == @last_event_count
end

Then /^(un)?scheduled maintenance should be generated(?: for check '([\w\.\-]+)' on entity '([\w\.\-]+)')?$/ do |unsched, check, entity|
  check  ||= @check
  entity ||= @entity

  entity_check = Flapjack::Data::Check.intersect(:entity_name => entity, :name => check).all.first
  entity_check.should_not be_nil

  entity_check.should (unsched ? be_in_unscheduled_maintenance : be_in_scheduled_maintenance)
end

Then /^show me the (\w+ )*log$/ do |adjective|
  puts "the #{adjective}log:"
  puts @logger.messages.join("\n")
end

Then /^dump notification rules for user (\d+)$/ do |contact|
  rule_ids = Flapjack.redis.smembers("contact_notification_rules:#{contact}")
  puts "There #{(rule_ids.length == 1) ? 'is' : 'are'} #{rule_ids.length} notification rule#{(rule_ids.length == 1) ? '' : 's'} for user #{contact}:"
  rule_ids.each {|rule_id|
    rule = Flapjack::Data::Notificationule.find_by_id(rule_id)
    puts rule.to_json
  }
end

# added for notification rules:
Given /^the following entities exist:$/ do |entities|
  entities.hashes.each do |entity_data|
    entity = find_or_create_entity(entity_data)

    next if entity_data['contacts'].nil?
    entity_data['contacts'].split(',').map(&:strip).each do |contact_id|
      contact = Flapjack::Data::Contact.find_by_id(contact_id)
      contact.should_not be_nil
      entity.contacts << contact
    end
  end
end

Given /^the following users exist:$/ do |contacts|
  contacts.hashes.each do |contact_data|

    contact = find_or_create_contact(contact_data)
    contact.timezone = contact_data['timezone']
    contact.save.should be_true

    ['email', 'sms'].each do |type|
      medium = Flapjack::Data::Medium.new(:type => type,
        :address => contact_data[type], :interval => 600)
      medium.save.should be_true
      contact.media << medium
    end
  end
end

Given /^user (\d+) has the following notification intervals:$/ do |contact_id, intervals|
  contact = Flapjack::Data::Contact.find_by_id(contact_id)
  intervals.hashes.each do |interval|
    @logger.info interval
    ['email', 'sms'].each do |type|
      medium = contact.media.intersect(:type => type).all.first
      medium.should_not be_nil
      medium.interval = interval[type].to_i
      medium.save.should be_true
      @logger.info "saved medium #{medium.inspect}"
    end
  end
end

Given /^user (\d+) has the following notification rollup thresholds:$/ do |contact_id, rollup_thresholds|
  contact = Flapjack::Data::Contact.find_by_id(contact_id)
  rollup_thresholds.hashes.each do |rollup_threshold|
    ['email', 'sms'].each do |type|
      if medium = contact.media.intersect(:type => type).all.first
        medium.rollup_threshold = rollup_threshold[type].to_i
        medium.save
      end
    end
  end
end

Given /^user (\d+) has the following notification rules:$/ do |contact_id, rules|
  contact = Flapjack::Data::Contact.find_by_id(contact_id)
  timezone = contact.time_zone

  # delete any autogenerated rules (evading autogeneration wrapper)

  notification_rules = contact.orig_notification_rules

  notification_rules.all.each do |rule|
    contact.orig_notification_rules.delete(rule)
    rule.destroy
  end

  rules.hashes.each do |rule|
    entities           = rule['entities']           ? rule['entities'].split(',').map(&:strip)        : []
    tags               = rule['tags']               ? rule['tags'].split(',').map(&:strip)            : []
    unknown_media      = rule['unknown_media']      ? rule['unknown_media'].split(',').map(&:strip)   : []
    warning_media      = rule['warning_media']      ? rule['warning_media'].split(',').map(&:strip)   : []
    critical_media     = rule['critical_media']     ? rule['critical_media'].split(',').map(&:strip)  : []
    unknown_blackhole  = rule['unknown_blackhole']  ? (rule['unknown_blackhole'].downcase == 'true')  : false
    warning_blackhole  = rule['warning_blackhole']  ? (rule['warning_blackhole'].downcase == 'true')  : false
    critical_blackhole = rule['critical_blackhole'] ? (rule['critical_blackhole'].downcase == 'true') : false
    time_restrictions  = rule['time_restrictions']  ? rule['time_restrictions'].split(',').map(&:strip).
      inject([]) { |memo, time_restriction|
      case time_restriction
      when '8-18 weekdays'
        weekdays_8_18 = IceCube::Schedule.new(timezone.local(2013,2,1,8,0,0), :duration => 60 * 60 * 10)
        weekdays_8_18.add_recurrence_rule(IceCube::Rule.weekly.day(:monday, :tuesday, :wednesday, :thursday, :friday))
        memo << icecube_schedule_to_time_restriction(weekdays_8_18, timezone)
      end
    } : []
    rule_data = {:entities           => Set.new(entities),
                 :tags               => Set.new(tags),
                 :unknown_media      => Set.new(unknown_media),
                 :warning_media      => Set.new(warning_media),
                 :critical_media     => Set.new(critical_media),
                 :unknown_blackhole  => unknown_blackhole,
                 :warning_blackhole  => warning_blackhole,
                 :critical_blackhole => critical_blackhole,
                 :time_restrictions  => time_restrictions}
    new_rule = Flapjack::Data::NotificationRule.new(rule_data)
    new_rule.save.should be_true
    notification_rules << new_rule
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
