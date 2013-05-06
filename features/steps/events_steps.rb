#!/usr/bin/env ruby

def drain_events
  loop do
    event = Flapjack::Data::Event.next(:block => false, :redis => @redis)
    break unless event
    @app.send(:process_event, event)
  end
end

def submit_event(event)
  @redis.rpush 'events', event.to_json
end

def set_scheduled_maintenance(entity, check, duration = 60*60*2)
  entity_check = Flapjack::Data::EntityCheck.for_entity_name(entity, check, :redis => @redis)
  t = Time.now.to_i
  entity_check.create_scheduled_maintenance(:start_time => t, :duration => duration, :summary => "upgrading everything")
  @redis.setex("#{entity}:#{check}:scheduled_maintenance", duration, t)
end

def remove_scheduled_maintenance(entity, check)
  entity_check = Flapjack::Data::EntityCheck.for_entity_name(entity, check, :redis => @redis)
  sm = entity_check.maintenances(nil, nil, :scheduled => true)
  sm.each do |m|
    entity_check.delete_scheduled_maintenance(:start_time => m[:start_time])
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

def submit_acknowledgement(entity, check)
  event = {
    'type'               => 'action',
    'state'              => 'acknowledgement',
    'summary'            => "I'll have this fixed in a jiffy, saw the same thing yesterday",
    'entity'             => entity,
    'check'              => check,
    'client'             => 'clientx',
    # 'acknowledgement_id' =>
  }
  submit_event(event)
end

# move back to notification
def icecube_hash_to_time_restriction(tr, time_zone)
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
                              'name'     => entity},
                             :redis => @redis )
end

Given /^(?:the check|check '([\w\.\-]+)' for entity '([\w\.\-]+)') is in an ok state$/ do |check, entity|
  check  = check  ? check  : @check
  entity = entity ? entity : @entity
  remove_unscheduled_maintenance(entity, check)
  remove_scheduled_maintenance(entity, check)
  remove_notifications(entity, check)
  set_ok_state(entity, check)
end

Given /^(?:the check|check '([\w\.\-]+)' for entity '([\w\.\-]+)') is in a critical state$/ do |check, entity|
  check  = check  ? check  : @check
  entity = entity ? entity : @entity
  remove_unscheduled_maintenance(entity, check)
  remove_scheduled_maintenance(entity, check)
  remove_notifications(entity, check)
  set_critical_state(entity, check)
end

Given /^(?:the check|check '([\w\.\-]+)' for entity '([\w\.\-]+)') is in scheduled maintenance$/ do |check, entity|
  check  = check  ? check  : @check
  entity = entity ? entity : @entity
  remove_unscheduled_maintenance(entity, check)
  set_scheduled_maintenance(entity, check)
end

# TODO set the state directly rather than submit & drain
Given /^(?:the check|check '([\w\.\-]+)' for entity '([\w\.\-]+)') is in unscheduled maintenance$/ do |check, entity|
  check  = check  ? check  : @check
  entity = entity ? entity : @entity
  remove_scheduled_maintenance(entity, check)
  set_critical_state(entity, check)
  submit_acknowledgement(entity, check)
  drain_events  # TODO these should only be in When clauses
end

Given /^the check is check '(.*)' on entity '([\w\.\-]+)'$/ do |check, entity|
  @check  = check
  @entity = entity
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

When /^an acknowledgement .*is received(?: for check '([\w\.\-]+)' on entity '([\w\.\-]+)')?$/ do |check, entity|
  check  ||= @check
  entity ||= @entity
  submit_acknowledgement(entity, check)
  drain_events
end

# TODO logging is a side-effect, should test for notification generation itself
Then /^a notification should not be generated(?: for check '([\w\.\-]+)' on entity '([\w\.\-]+)')?$/ do |check, entity|
  check  ||= @check
  entity ||= @entity
  message = @logger.messages.find_all {|m| m =~ /enerating notifications for event #{entity}:#{check}/ }.last
  found = message ? message.match(/Not generating notifications/) : false
  found.should be_true
end

Then /^a notification should be generated(?: for check '([\w\.\-]+)' on entity '([\w\.\-]+)')?$/ do |check, entity|
  check  ||= @check
  entity ||= @entity
  message = @logger.messages.find_all {|m| m =~ /enerating notifications for event #{entity}:#{check}/ }.last
  found = message ? message.match(/Generating notifications/) : false
  found.should be_true
end

Then /^show me the log$/ do
  puts @logger.messages.join("\n")
end

# added for notification rules:

Given /^the following entities exist:$/ do |entities|
  entities.hashes.each do |entity|
    contacts = entity['contacts'].split(',')
    contacts.map! do |contact|
      contact.strip
    end
    #puts "adding entity #{entity['name']} (#{entity['id']}) with contacts: [#{contacts.join(', ')}]"
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
                                :redis => @redis )
  end
end

Given /^user (\d+) has the following notification intervals:$/ do |contact_id, intervals|
  contact = Flapjack::Data::Contact.find_by_id(contact_id, :redis => @redis)
  intervals.hashes.each do |interval|
    contact.set_interval_for_media('email', interval['email'].to_i * 60)
    contact.set_interval_for_media('sms',   interval['sms'].to_i * 60)
  end
end

Given /^user (\d+) has the following notification rules:$/ do |contact_id, rules|
  rules.hashes.each do |rule|
    entities           = rule['entities'].split(',').map { |x| x.strip }
    entity_tags        = rule['entity_tags'].split(',').map { |x| x.strip }
    warning_media      = rule['warning_media'].split(',').map { |x| x.strip }
    critical_media     = rule['critical_media'].split(',').map { |x| x.strip }
    warning_blackhole  = (rule['warning_blackhole'].downcase == 'true')
    critical_blackhole = (rule['critical_blackhole'].downcase == 'true')
    time_zone = ActiveSupport::TimeZone.new("America/New_York")
    time_restrictions  = []
    rule['time_restrictions'].split(',').map { |x| x.strip }.each do |time_restriction|
      case time_restriction
      when '8-18 weekdays'
        # FIXME: get timezone from the user definition (or config[:default_contact_timezone])
        weekdays_8_18 = IceCube::Schedule.new(time_zone.local(2013,2,1,8,0,0), :duration => 60 * 60 * 10)
        weekdays_8_18.add_recurrence_rule(IceCube::Rule.weekly.day(:monday, :tuesday, :wednesday, :thursday, :friday))
        time_restrictions << icecube_hash_to_time_restriction(weekdays_8_18.to_hash, time_zone)
      end
    end
    rule_data = {:contact_id         => contact_id,
                 :entities           => entities,
                 :entity_tags        => entity_tags,
                 :warning_media      => warning_media,
                 :critical_media     => critical_media,
                 :warning_blackhole  => warning_blackhole,
                 :critical_blackhole => critical_blackhole,
                 :time_restrictions  => time_restrictions}
    Flapjack::Data::NotificationRule.add(rule_data, time_zone, :redis => @redis)
  end
end

Then /^all alert dropping keys for user (\d+) should have expired$/ do |contact_id|
  @redis.keys("drop_alerts_for_contact:#{contact_id}*").should be_empty
end

# When /^the (\w*) alert block for user (\d*) for (?:the check|check '([\w\.\-]+)' for entity '([\w\.\-]+)') for state (.*) expires$/ do |media, contact, check, entity, state|
#   check  = check  ? check  : @check
#   entity = entity ? entity : @entity
#   num_deleted = @redis.del("drop_alerts_for_contact:#{contact}:#{media}:#{entity}:#{check}:#{state}")
#   puts "Warning: no keys expired" unless num_deleted > 0
# end

Then /^(.*) email alert(?:s)? should be queued for (.*)$/ do |num_queued, address|
  check  = check  ? check  : @check
  entity = entity ? entity : @entity
  case num_queued
  when 'no'
    num_queued = 0
  end
  queue  = Resque.peek('email_notifications', 0, 30)
  queue.find_all {|n| n['args'].first['address'] == address }.length.should == num_queued.to_i
end
