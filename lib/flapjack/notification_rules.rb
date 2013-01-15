tuple = [
  [ alice, sms ],
  [ alice, email ],
  [ boby, email ],
  [ carol, sms ],
]

event

# delete media based on entity name(s), tags, severity, time of day
tuple.map! do |contact, media|
  rules    = contact.notification_rules
  # filter based on tags, severity, time of day
  matchers = rules.find_all do |rule|
    rule.match?(event, contact, media)
  end
  matchers.empty? ? nil : [ contact, media, matchers ]
end

# matchers are rules of the contact that have matched the current (event, contac, media) tuple
# but matched it how? ... details schmetails

tuple.compact!

# tuple = [
#   [ alice, sms, matchers ],
#   [ boby, email, matchers ],
# ]

# delete media based on blackholes
tuple.find_all do |contact, media, matchers|
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

