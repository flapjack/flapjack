
# copied from flapjack-populator
def add_contact(contact = {})
  @redis.multi
  @redis.del("contact:#{contact['id']}")
  @redis.del("contact_media:#{contact['id']}")
  @redis.hset("contact:#{contact['id']}", 'first_name', contact['first_name'])
  @redis.hset("contact:#{contact['id']}", 'last_name',  contact['last_name'])
  @redis.hset("contact:#{contact['id']}", 'email',      contact['email'])
  contact['media'].each_pair {|medium, address|
    @redis.hset("contact_media:#{contact['id']}", medium, address)
  }    
  @redis.exec
end

# also copied from flapjack-populator
def add_entity(entity = {})
  @redis.multi 
  existing_name = @redis.hget("entity:#{entity['id']}", 'name')
  @redis.del("entity_id:#{existing_name}") unless existing_name == entity['name']
  @redis.set("entity_id:#{entity['name']}", entity['id'])
  @redis.hset("entity:#{entity['id']}", 'name', entity['name'])

  @redis.del("contacts_for:#{entity['id']}")
  entity['contacts'].each {|contact|
    @redis.sadd("contacts_for:#{entity['id']}", contact)
  }
  @redis.exec
end

Given /^the user wants to receive SMS notifications for entity '([\w\.\-]+)'$/ do |entity|
  add_contact( 'id'         => '0999',
               'first_name' => 'John',
               'last_name'  => 'Smith',
               'email'      => 'johns@example.dom',
               'media'      => {'sms' => '+61888888888'} )
  add_entity( 'id'       => '5000',
              'name'     => entity,
              'contacts' => ["0999"])
end

Given /^the user wants to receive email notifications for entity '([\w\.\-]+)'$/ do |entity|
  add_contact( 'id'         => '0999',
               'first_name' => 'John',
               'last_name'  => 'Smith',
               'email'      => 'johns@example.dom',
               'media'      => {'email' => 'johns@example.dom'} )
  add_entity( 'id'       => '5000',
              'name'     => entity,
              'contacts' => ["0999"] )
end

Given /^the user wants to receive SMS notifications for entity '([\w\.\-]+)' and email notifications for entity '([\w\.\-]+)'$/ do |entity1, entity2|
  add_contact( 'id'         => '0998',
               'first_name' => 'John',
               'last_name'  => 'Smith',
               'email'      => 'johns@example.dom',
               'media'      => {'sms' => '+61888888888'} )
  add_contact( 'id'         => '0999',
               'first_name' => 'John',
               'last_name'  => 'Smith',
               'email'      => 'johns@example.dom',
               'media'      => {'email'      => 'johns@example.dom'} )
  add_entity( 'id'       => '5000',
              'name'     => entity1,
              'contacts' => ["0998"])
  add_entity( 'id'       => '5001',
              'name'     => entity2,
              'contacts' => ["0999"])              
end

When /^an event notification is generated for entity '([\w\.\-]+)'$/ do |entity|
  event = Flapjack::Event.new('type'    => 'service',
                              'state'   => 'critical',
                              'summary' => '100% packet loss',
                              'entity'  => entity,
                              'check'   => 'ping')
  @app.generate_notification(event)
end

Then /^an SMS notification for entity '([\w\.\-]+)' should be queued for the user$/ do |entity|
  queue = ResqueSpec.peek(Flapjack::Notification::Sms.instance_variable_get('@queue'))
  queue.select {|n| n[:args].first['event_id'] =~ /#{entity}:ping/ }.should_not be_empty
end

Then /^an email notification for entity '([\w\.\-]+)' should be queued for the user$/ do |entity|
  queue = ResqueSpec.peek(Flapjack::Notification::Email.instance_variable_get('@queue'))
  queue.select {|n| n[:args].first['event_id'] =~ /#{entity}:ping/ }.should_not be_empty
end

Then /^an SMS notification for entity '([\w\.\-]+)' should not be queued for the user$/ do |entity|
  queue = ResqueSpec.peek(Flapjack::Notification::Sms.instance_variable_get('@queue'))
  queue.select {|n| n[:args].first['event_id'] =~ /#{entity}:ping/ }.should be_empty
end

Then /^an email notification for entity '([\w\.\-]+)' should not be queued for the user$/ do |entity|
  queue = ResqueSpec.peek(Flapjack::Notification::Email.instance_variable_get('@queue'))
  queue.select {|n| n[:args].first['event_id'] =~ /#{entity}:ping/ }.should be_empty
end

Given /^a user SMS notification has been queued$/ do
  @sms_notification = {'notification_type'  => 'problem',
                       'contact_first_name' => 'John',
                       'contact_last_name'  => 'Smith',
                       'state'              => 'CRITICAL',
                       'summary'            => 'Socket timeout after 10 seconds',
                       'time'               => Time.now.to_i,
                       'event_id'           => 'b99999.darwin03-viprion-blade8:CHECK',
                       'address'            => '+61412345678',
                       'id'                 => 1}
end

Given /^a user email notification has been queued$/ do
  @email_notification = {'notification_type' => 'problem',
                        'contact_first_name' => 'John',
                        'contact_last_name'  => 'Smith',
                        'state'              => 'CRITICAL',
                        'summary'            => 'Socket timeout after 10 seconds',
                        'time'               => Time.now.to_i,
                        'event_id'           => 'b99999.darwin03-viprion-blade8:CHECK',
                        'address'            => 'johns@example.dom',
                        'id'                 => 2}
end

# TODO may need to get more complex, depending which SMS provider is used
When /^the SMS notification handler runs successfully$/ do
  # returns success by default - currently matches all addresses, maybe load from config?
  stub_request(:get, /.*/)

  lambda {
    Flapjack::Notification::Sms.new.perform(@sms_notification)
  }.should_not raise_error
  @sms_sent = true
end

When /^the SMS notification handler fails to send an SMS$/ do
  stub_request(:any, /.*/).to_return(:status => [500, "Internal Server Error"])

  lambda {
    Flapjack::Notification::Sms.new.perform(@sms_notification)
  }.should raise_error
  @sms_sent = false
end

When /^the email notification handler runs successfully$/ do
  lambda {
    Flapjack::Notification::Email.new.perform(@email_notification)
  }.should_not raise_error
end

# This doesn't work as I have it here -- sends a mail with an empty To: header instead.
# Might have to introduce Rspec's stubs here to fake bad mailer behaviour -- or if mail sending
# won't ever fail, don't test for failure? 
When /^the email notification handler fails to send an email$/ do
  pending
  @email_notification['address'] = nil  
  send_email(@email_notification)
end

Then /^the user should receive an SMS notification$/ do
  @sms_sent.should be_true
end

Then /^the user should receive an email notification$/ do
  ActionMailer::Base.deliveries.should_not be_empty
  ActionMailer::Base.deliveries.should have(1).mail
end

Then /^the user should not receive an SMS notification$/ do
  @sms_sent.should be_false
end

Then /^the user should not receive an email notification$/ do
  ActionMailer::Base.deliveries.should be_empty
end
