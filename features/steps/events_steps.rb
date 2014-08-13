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
  Flapjack.redis.rpush 'events', event.to_json
end

def set_scheduled_maintenance(entity_name, check_name, duration)
  entity = Flapjack::Data::Entity.intersect(:name => entity_name).all.first
  expect(entity).not_to be_nil
  check = entity.checks.intersect(:name => check_name).all.first
  expect(check).not_to be_nil

  t = Time.now
  sched_maint = Flapjack::Data::ScheduledMaintenance.new(:start_time => t,
    :end_time => Time.at(t.to_i + duration), :summary => 'upgrading everything')
  expect(sched_maint.save).to be true
  check.add_scheduled_maintenance(sched_maint)
end

def remove_scheduled_maintenance(entity_name, check_name)
  entity = Flapjack::Data::Entity.intersect(:name => entity_name).all.first
  expect(entity).not_to be_nil
  check = entity.checks.intersect(:name => check_name).all.first
  expect(check).not_to be_nil

  t = Time.now
  sched_maints = check.scheduled_maintenances_by_start.all
  sched_maints.each do |sm|
    check.end_scheduled_maintenance(sm, t)
    sched_maint.destroy
  end
end

def set_unscheduled_maintenance(entity_name, check_name, duration)
  entity = Flapjack::Data::Entity.intersect(:name => entity_name).all.first
  expect(entity).not_to be_nil
  check = entity.checks.intersect(:name => check_name).all.first
  expect(check).not_to be_nil

  t = Time.now
  unsched_maint = Flapjack::Data::UnscheduledMaintenance.new(:start_time => t,
    :end_time => Time.at(t.to_i + duration), :summary => 'fixing now')
  expect(unsched_maint.save).to be true
  check.set_unscheduled_maintenance(unsched_maint)
end

def clear_unscheduled_maintenance(entity_name, check_name)
  entity = Flapjack::Data::Entity.intersect(:name => entity_name).all.first
  expect(entity).not_to be_nil
  check = entity.checks.intersect(:name => check_name).all.first
  expect(check).not_to be_nil

  check.clear_unscheduled_maintenance(Time.now)
end

def set_state(entity_name, check_name, state, last_update)
  entity = Flapjack::Data::Entity.intersect(:name => entity_name).all.first
  expect(entity).not_to be_nil
  check = entity.checks.intersect(:name => check_name).all.first
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
    'type'               => 'action',
    'state'              => 'acknowledgement',
    'summary'            => "I'll have this fixed in a jiffy, saw the same thing yesterday",
    'entity'             => entity_name,
    'check'              => check_name,
  }
  submit_event(event)
end

def submit_test(entity_name, check_name)
  event = {
    'type'               => 'action',
    'state'              => 'test_notifications',
    'summary'            => "test notification for all contacts interested in #{entity_name}",
    'entity'             => entity_name,
    'check'              => check_name,
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

Given /^an entity '([\w\.\-]+)' exists$/ do |entity_name|
  entity = Flapjack::Data::Entity.intersect(:name => entity_name).all.first
  if entity.nil?
    entity = Flapjack::Data::Entity.new(:id   => '5000',
                                        :name => entity_name)
    expect(entity.save).to be true
  end
end

Given /^the check is check '(.*)' on entity '([\w\.\-]+)'$/ do |check_name, entity_name|
  entity = Flapjack::Data::Entity.intersect(:name => entity_name).all.first
  expect(entity).not_to be_nil

  check = entity.checks.intersect(:name => check_name).all.first
  if check.nil?
    check = Flapjack::Data::Check.new(:name => check_name)
    expect(check.save).to be true
  end
  entity.checks << check

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

  entity = Flapjack::Data::Entity.intersect(:name => entity_name).all.first
  expect(entity).not_to be_nil
  check = entity.checks.intersect(:name => check_name).all.first
  expect(check).not_to be_nil

  if last_notification = check.last_notification
    puts @logger.messages.join("\n\n") if last_notification.last_notification_count == @last_event_count
    expect(last_notification.last_notification_count).not_to eq(@last_event_count)
  end
end

Then /^a notification should be generated(?: for check '([\w\.\-]+)' on entity '([\w\.\-]+)')?$/ do |check_name, entity_name|
  check_name  ||= @check_name
  entity_name ||= @entity_name

  entity = Flapjack::Data::Entity.intersect(:name => entity_name).all.first
  expect(entity).not_to be_nil
  check = entity.checks.intersect(:name => check_name).all.first
  expect(check).not_to be_nil

  last_notification = check.last_notification
  expect(last_notification).not_to be_nil
  puts @logger.messages.join("\n\n") if last_notification.last_notification_count != @last_event_count
  expect(last_notification.last_notification_count).to eq(@last_event_count)
end

Then /^(un)?scheduled maintenance should be generated(?: for check '([\w\.\-]+)' on entity '([\w\.\-]+)')?$/ do |unsched, check_name, entity_name|
  check_name  ||= @check_name
  entity_name ||= @entity_name

  entity = Flapjack::Data::Entity.intersect(:name => entity_name).all.first
  expect(entity).not_to be_nil
  check = entity.checks.intersect(:name => check_name).all.first
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
      expect(contact).not_to be_nil
      entity.contacts << contact
    end
  end
end

Given /^the following users exist:$/ do |contacts|
  contacts.hashes.each do |contact_data|

    contact = find_or_create_contact(contact_data)
    contact.timezone = contact_data['timezone']
    expect(contact.save).to be true

    ['email', 'sms'].each do |type|
      medium = Flapjack::Data::Medium.new(:type => type,
        :address => contact_data[type], :interval => 600)
      expect(medium.save).to be true
      contact.media << medium
    end
  end
end

Given /^user (\S+) has the following notification intervals:$/ do |contact_id, intervals|
  contact = Flapjack::Data::Contact.find_by_id(contact_id)
  intervals.hashes.each do |interval|
    @logger.info interval
    ['email', 'sms'].each do |type|
      medium = contact.media.intersect(:type => type).all.first
      expect(medium).not_to be_nil
      medium.interval = interval[type].to_i
      expect(medium.save).to be true
      @logger.info "saved medium #{medium.inspect}"
    end
  end
end

Given /^user (\S+) has the following notification rollup thresholds:$/ do |contact_id, rollup_thresholds|
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

Given /^user (\S+) has the following notification rules:$/ do |contact_id, rules|
  contact = Flapjack::Data::Contact.find_by_id(contact_id)
  timezone = contact.time_zone

  # delete any autogenerated rules (evading autogeneration wrapper)

  notification_rules = contact.orig_notification_rules

  notification_rules.all.each do |rule|
    contact.orig_notification_rules.delete(rule)
    rule.destroy
  end

  rules.hashes.each do |rule|
    entities           = rule['entities']      ? rule['entities'].split(',').map(&:strip)       : []
    tags               = rule['tags']          ? rule['tags'].split(',').map(&:strip)           : []
    media = {
      :unknown  => (rule['unknown_media']      ? rule['unknown_media'].split(',').map(&:strip)  : []),
      :warning  => (rule['warning_media']      ? rule['warning_media'].split(',').map(&:strip)  : []),
      :critical => (rule['critical_media']     ? rule['critical_media'].split(',').map(&:strip) : [])
    }
    blackhole = {
      :unknown  => (rule['unknown_blackhole']  ? (rule['unknown_blackhole'].downcase == 'true')  : false),
      :warning  => (rule['warning_blackhole']  ? (rule['warning_blackhole'].downcase == 'true')  : false),
      :critical => (rule['critical_blackhole'] ? (rule['critical_blackhole'].downcase == 'true') : false)
    }
    time_restrictions  = rule['time_restrictions']  ? rule['time_restrictions'].split(',').map(&:strip).
      inject([]) { |memo, time_restriction|
      case time_restriction
      when '8-18 weekdays'
        weekdays_8_18 = IceCube::Schedule.new(timezone.local(2013,2,1,8,0,0), :duration => 60 * 60 * 10)
        weekdays_8_18.add_recurrence_rule(IceCube::Rule.weekly.day(:monday, :tuesday, :wednesday, :thursday, :friday))
        memo << icecube_schedule_to_time_restriction(weekdays_8_18, timezone)
      end
    } : []

    state_data = {:media => media, :blackhole => blackhole}

    rule_data = {:entities           => Set.new(entities),
                 :tags               => Set.new(tags),
                 :time_restrictions  => time_restrictions}
    new_rule = Flapjack::Data::NotificationRule.new(rule_data)
    expect(new_rule.save).to be true

    nr_fail_states = Flapjack::Data::CheckState.failing_states.collect do |fail_state|
      state = Flapjack::Data::NotificationRuleState.new(:state => fail_state,
        :blackhole => state_data[:blackhole][fail_state.to_sym])
      state.save

      media_types = state_data[:media][fail_state.to_sym]
      unless media_types.empty?
        state_media = contact.media.intersect(:type => media_types).all
        state.media.add(*state_media) unless state_media.empty?
      end
      state
    end
    new_rule.states.add(*nr_fail_states)

    notification_rules << new_rule
  end
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

When(/^user (\S+) ceases to be a contact of entity '(.*)'$/) do |contact_id, entity_name|
  entity = Flapjack::Data::Entity.intersect(:name => entity_name).all.first
  expect(entity).not_to be_nil
  contact = Flapjack::Data::Contact.find_by_id(contact_id)
  expect(contact).not_to be_nil

  entity.contacts.delete(contact)
end
