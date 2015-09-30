#!/usr/bin/env ruby

def drain_events
  loop do
    event = Flapjack::Data::Event.next('events', :block => false,
      :redis => @redis)
    break unless event
    @processor.send(:process_event, event)
  end
  drain_notifications
end

def drain_notifications
  return unless @notifier_redis
  loop do
    notification = Flapjack::Data::Notification.next('notifications',
      :block => false, :redis => @notifier_redis)
    break unless notification
    @notifier.send(:process_notification, notification)
  end
end

def drain_alerts(queue, gateway)
  return unless @notifier_redis
  loop do
    alert = Flapjack::Data::Alert.next(queue, :block => false,
      :redis => @notifier_redis, :logger => @logger)
    break unless alert
    gateway.send(:deliver, alert)
  end
end

def submit_event(event)
  @redis.rpush('events', Flapjack.dump_json(event))
end

def set_scheduled_maintenance(entity, check, duration)
  entity_check = Flapjack::Data::EntityCheck.for_entity_name(entity, check, :redis => @redis)
  t = Time.now.to_i
  entity_check.create_scheduled_maintenance(t, duration, :summary => "upgrading everything")
  @redis.setex("#{entity}:#{check}:scheduled_maintenance", duration, t)
end

def remove_scheduled_maintenance(entity, check)
  entity_check = Flapjack::Data::EntityCheck.for_entity_name(entity, check, :redis => @redis)
  sm = entity_check.maintenances(nil, nil, :scheduled => true)
  sm.each do |m|
    entity_check.end_scheduled_maintenance(m[:start_time])
  end
end

def remove_unscheduled_maintenance(entity, check)
  # end any unscheduled downtime
  event_id = entity + ":" + check
  if (um_start = @redis.get("#{event_id}:unscheduled_maintenance"))
    @redis.del("#{event_id}:unscheduled_maintenance")
    duration = Time.now.to_i - um_start.to_i
    @redis.zadd("#{event_id}:unscheduled_maintenances", duration, um_start)
  end
end

def remove_notifications(entity, check)
  event_id = entity + ":" + check
  @redis.del("#{event_id}:last_problem_notification")
  @redis.del("#{event_id}:last_recovery_notification")
  @redis.del("#{event_id}:last_acknowledgement_notification")
end

def set_ok_state(entity, check)
  entity_check = Flapjack::Data::EntityCheck.for_entity_name(entity, check, :redis => @redis)
  entity_check.update_state(Flapjack::Data::EntityCheck::STATE_OK,
    :timestamp => (Time.now.to_i - (60*60*24)))
end

def set_critical_state(entity, check)
  entity_check = Flapjack::Data::EntityCheck.for_entity_name(entity, check, :redis => @redis)
  entity_check.update_state(Flapjack::Data::EntityCheck::STATE_CRITICAL,
    :timestamp => (Time.now.to_i - (60*60*24)))
end

def set_warning_state(entity, check)
  entity_check = Flapjack::Data::EntityCheck.for_entity_name(entity, check, :redis => @redis)
  entity_check.update_state(Flapjack::Data::EntityCheck::STATE_WARNING,
    :timestamp => (Time.now.to_i - (60*60*24)))
end

def end_unscheduled_maintenance(entity, check)
  entity_check = Flapjack::Data::EntityCheck.for_entity_name(entity, check, :redis => @redis)
  entity_check.end_unscheduled_maintenance(Time.now.to_i)
end

# Construct and submit an event
# @param kind: one of 'ok','warning', 'critical', 'unknown', 'acknowledgement', 'test_notifications'
def one_event(kind, entity, check, details:nil)
  event = {
      'type'               => 'service',
      'state'              => kind,
      'summary'            => "",
      'entity'             => entity,
      'check'              => check
  }
  event['details'] = details unless details.nil?
  case kind
    when 'ok'
      event['summary'] = '0% packet loss'
    when 'warning'
      event['summary'] = '25% packet loss'
    when 'critical'
      event['summary'] = '100% packet loss'
    when 'unknown'
      event['summary'] = 'check execution error'
    when 'acknowledgement'
      event['type'] = 'action'
      event['summary'] = "I'll have this fixed in a jiffy, saw the same thing yesterday"
    when 'test'
      event['type'] = 'action'
      event['state'] = 'test_notifications'
      event['summary'] = "test notification for all contacts interested in #{entity}"
  end
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

  tr
end

Given /^an entity '([\w\.\-]+)' exists$/ do |entity|
  Flapjack::Data::Entity.add({'id'       => '5000',
                              'name'     => entity},
                             :redis => @redis )
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
  @redis.hdel("check:#{@key}", 'state')
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

When /^an? ((?:ok)|(?:failure)|(?:critical)|(?:warning)|(?:unknown)|(?:acknowledgement)|(?:test)) event is received(?: for check '([\w\.\-]+)' on entity '([\w\.\-]+)')?(?: with details '([^']+)')?$/ do |kind, check, entity, details|
  check  ||= @check
  entity ||= @entity
  one_event(kind, entity, check, details:details)
  drain_events
end

When /^the unscheduled maintenance is ended(?: for check '([\w\.\-]+)' on entity '([\w\.\-]+)')?$/ do |check, entity|
  check  ||= @check
  entity ||= @entity
  end_unscheduled_maintenance(entity, check)
end

When /^check '([\w\.\-]+)' (?:for|on) entity '([\w\.\-]+)' is (dis|en)abled$/ do |check, entity, dis_en|
  entity_check = Flapjack::Data::EntityCheck.for_entity_name(entity, check, :redis => @redis)
  case dis_en
  when 'dis'
    entity_check.disable!
  when 'en'
    entity_check.enable!
  end
end

# TODO logging is a side-effect, should test for notification generation itself
Then /^a notification should not be generated(?: for check '([\w\.\-]+)' on entity '([\w\.\-]+)')?$/ do |check, entity|
  check  ||= @check
  entity ||= @entity
  message = @logger.messages.find_all {|m| m =~ /enerating notification for event #{entity}:#{check}/ }.last
  found = message ? message.match(/Not generating notification/) : false
  expect(found).to be_truthy
end

Then /^a notification should be generated(?: for check '([\w\.\-]+)' on entity '([\w\.\-]+)')?$/ do |check, entity|
  check  ||= @check
  entity ||= @entity
  message = @logger.messages.find_all {|m| m =~ /enerating notification for event #{entity}:#{check}/ }.last
  found = message ? message.match(/Generating notification/) : false
  expect(found).to be_truthy
end

Then /^(un)?scheduled maintenance should be generated(?: for check '([\w\.\-]+)' on entity '([\w\.\-]+)')?$/ do |unsched, check, entity|
  check  ||= @check
  entity ||= @entity
  expect(@redis.get("#{entity}:#{check}:#{unsched || ''}scheduled_maintenance")).not_to be_nil
end

Then /^show me the (\w+ )*log$/ do |adjective|
  puts "the #{adjective}log:"
  puts @logger.messages.join("\n")
end

Then /^dump notification rules for user (\S+)$/ do |contact|
  rule_ids = @redis.smembers("contact_notification_rules:#{contact}")
  puts "There #{(rule_ids.length == 1) ? 'is' : 'are'} #{rule_ids.length} notification rule#{(rule_ids.length == 1) ? '' : 's'} for user #{contact}:"
  rule_ids.each {|rule_id|
    rule = Flapjack::Data::NotificationRule.find_by_id(rule_id, :redis => @redis)
    puts Flapjack.dump_json(rule)
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
                                'contacts' => contacts},
                               :redis => @redis )
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
                                 'media'      => media},
                                :redis => @redis ).timezone = contact['timezone']
  end
end

Given /^user (\S+) has the following notification intervals:$/ do |contact_id, intervals|
  contact = Flapjack::Data::Contact.find_by_id(contact_id, :redis => @redis)
  intervals.hashes.each do |interval|
    contact.set_interval_for_media('email', interval['email'].to_i * 60)
    contact.set_interval_for_media('sms',   interval['sms'].to_i * 60)
  end
end

Given /^user (\S+) has the following notification rollup thresholds:$/ do |contact_id, rollup_thresholds|
  contact = Flapjack::Data::Contact.find_by_id(contact_id, :redis => @redis)
  rollup_thresholds.hashes.each do |rollup_threshold|
    contact.set_rollup_threshold_for_media('email', rollup_threshold['email'].to_i)
    contact.set_rollup_threshold_for_media('sms',   rollup_threshold['sms'].to_i)
  end
end

Given /^user (\S+) has the following notification rules:$/ do |contact_id, rules|
  contact = Flapjack::Data::Contact.find_by_id(contact_id, :redis => @redis)
  time_zone = contact.time_zone

  # delete any autogenerated rules, and do it using redis directly so no new
  # ones will be created
  contact.notification_rules.each do |nr|
    @redis.srem("contact_notification_rules:#{contact_id}", nr.id)
    @redis.del("notification_rule:#{nr.id}")
  end
  rules.hashes.each do |rule|
    entities           = rule['entities']           ? rule['entities'].split(',').map       {|x| x.strip } : []
    regex_entities     = rule['regex_entities']     ? rule['regex_entities'].split(',').map {|x| x.strip } : []
    tags               = rule['tags']               ? rule['tags'].split(',').map           {|x| x.strip } : []
    unknown_media      = rule['unknown_media']      ? rule['unknown_media'].split(',').map  {|x| x.strip } : []
    warning_media      = rule['warning_media']      ? rule['warning_media'].split(',').map  {|x| x.strip } : []
    critical_media     = rule['critical_media']     ? rule['critical_media'].split(',').map {|x| x.strip } : []
    unknown_blackhole  = rule['unknown_blackhole']  ? (rule['unknown_blackhole'].downcase == 'true')  : false
    warning_blackhole  = rule['warning_blackhole']  ? (rule['warning_blackhole'].downcase == 'true')  : false
    critical_blackhole = rule['critical_blackhole'] ? (rule['critical_blackhole'].downcase == 'true') : false
    time_restrictions  = rule['time_restrictions']  ? rule['time_restrictions'].split(',').map { |x|
      x.strip
    }.inject([]) { |memo, time_restriction|
      case time_restriction
      when '8-18 weekdays'
        weekdays_8_18 = IceCube::Schedule.new(time_zone.local(2013,2,1,8,0,0), :duration => 60 * 60 * 10)
        weekdays_8_18.add_recurrence_rule(IceCube::Rule.weekly.day(:monday, :tuesday, :wednesday, :thursday, :friday))
        memo << icecube_schedule_to_time_restriction(weekdays_8_18, time_zone)
      end
    } : []
    rule_data = {:contact_id         => contact_id,
                 :entities           => entities,
                 :regex_entities     => regex_entities,
                 :tags               => tags,
                 :unknown_media      => unknown_media,
                 :warning_media      => warning_media,
                 :critical_media     => critical_media,
                 :unknown_blackhole  => unknown_blackhole,
                 :warning_blackhole  => warning_blackhole,
                 :critical_blackhole => critical_blackhole,
                 :time_restrictions  => time_restrictions}
    created_rule = Flapjack::Data::NotificationRule.add(rule_data, :redis => @redis)
    unless created_rule.is_a?(Flapjack::Data::NotificationRule)
      raise "Error creating notification rule with data: #{rule_data}, errors: #{created_rule.join(', ')}"
    end
  end
end

Then /^all alert dropping keys for user (\S+) should have expired$/ do |contact_id|
  expect(@redis.keys("drop_alerts_for_contact:#{contact_id}:*")).to be_empty
end

Then /^(\w+) (\w+) alert(?:s)?(?: of)?(?: type (\w+))?(?: and)?(?: rollup (\w+))? should be queued for (.*)$/ do |num_queued, media, notification_type, rollup, address|
  check  = check  ? check  : @check
  entity = entity ? entity : @entity
  case num_queued
  when 'no'
    num_queued = 0
  end
  queued = redis_peek("#{media}_notifications", 0, 30)
  queued_length = queued.find_all {|n|
    type_ok = notification_type ? ( n['notification_type'] == notification_type ) : true
    rollup_ok = case rollup
    when 'none'
      n['rollup'].nil?
    when nil, n['rollup']
      true
    else
      false
    end
    type_ok && rollup_ok && ( n['address'] == address )
  }.length
  expect(queued_length).to eq(num_queued.to_i)
end

When(/^user (\S+) ceases to be a contact of entity '(.*)'$/) do |contact_id, entity|
  entity = Flapjack::Data::Entity.find_by_name(entity, :redis => @redis)
  @redis.srem("contacts_for:#{entity.id}", contact_id)
end

Then(/^(?:the check|check '([\w\.\-]+)' for entity '([\w\.\-]+)') should not appear in unacknowledged_failing$/) do |check, entity|
  check  ||= @check
  entity ||= @entity
  unacknowledged_failing_checks = Flapjack::Data::EntityCheck.unacknowledged_failing(:redis => @redis)
  expect(unacknowledged_failing_checks.map {|ec| "#{ec.entity.name}:#{ec.check}"}).to_not include("#{entity}:#{check}")
end

Then(/^(?:the check|check '([\w\.\-]+)' for entity '([\w\.\-]+)') should appear in unacknowledged_failing$/) do |check, entity|
  check  ||= @check
  entity ||= @entity
  unacknowledged_failing_checks = Flapjack::Data::EntityCheck.unacknowledged_failing(:redis => @redis)
  expect(unacknowledged_failing_checks.map {|ec| "#{ec.entity.name}:#{ec.check}"}).to include("#{entity}:#{check}")
end

