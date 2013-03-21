#!/usr/bin/env ruby



#tuple = [
#  [ alice, sms ],
#  [ alice, email ],
#  [ boby, email ],
#  [ carol, sms ],
#]

event

# delete media based on entity name(s), tags, severity, time of day
# first get all rules matching entity and time
tuple.map! do |contact, media|
  rules    = contact.notification_rules
  # filter based on tags, severity, time of day
  matchers = contact.notification_rules do |rule|
    rule.match_entity?(event) && rule.match_time?(event)
  end
  matchers.empty? ? nil : [ contact, media, matchers ]
end

# matchers are rules of the contact that have matched the current event
# for time and entity

tuple.compact!

# tuple = [
#   [ alice, sms, matchers ],
#   [ boby, email, matchers ],
# ]

# delete the matcher for all entities if there are more specific matchers
tuple = tuple.map do |contact, media, matchers|
  if matchers.lengh > 1
    have_specific = matchers.detect do |matcher|
      matcher.entities or matcher.entity_tags
    end
    if have_specific
      # delete the rule for all entities
      matchers.map! do |matcher|
        matcher.entities.nil? and matcher.entity_tags.nil? ? nil : matcher
      end
    end
  end
  [contact, media, matchers]
end

# delete media based on blackholes
tuple = tuple.find_all do |contact, media, matchers|
  matchers.none? {|matcher| matcher.blackhole? }
end

# tuple = [
#   [ alice, sms, matchers ],
# ]

# delete media based on notification interval
tuple.find_all do |contact, media, matchers|
  #interval = matchers.sort_by {|matcher| matcher.interval }.first # => 5
  interval = contact.interval_for_media(media) # => 5
  # use an expiring key to block a notification for a given (contact, media) for the interval
  not_notified_within(interval) # => true
end

# tuple = [
#   [ alice, sms, matchers ],
# ]

tuple.each {|contact, media, matchers| dispatch_message(media, contact) }

