
include Mail::Matchers

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

Given /^the user wants to receive SMS notifications for entity '([\w\.\-]+)'$/ do |entity|
  add_contact( 'id'         => '0999',
               'first_name' => 'John',
               'last_name'  => 'Smith',
               'email'      => 'johns@example.dom',
               'media'      => {'sms' => '+61888888888'} )
  add_entity( 'id'       => '5000',
              'name'     => entity,
              'contacts' => ["0999"] )
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
  event = Flapjack::Data::Event.new('type'    => 'service',
                                    'state'   => 'critical',
                                    'summary' => '100% packet loss',
                                    'entity'  => entity,
                                    'check'   => 'ping')
  @app.generate_notification(event)
end

Then /^an SMS notification for entity '([\w\.\-]+)' should be queued for the user$/ do |entity|
  queue = ResqueSpec.peek('sms_notifications')
  queue.select {|n| n[:args].first['event_id'] =~ /#{entity}:ping/ }.should_not be_empty
end

Then /^an email notification for entity '([\w\.\-]+)' should be queued for the user$/ do |entity|
  queue = ResqueSpec.peek('email_notifications')
  queue.select {|n| n[:args].first['event_id'] =~ /#{entity}:ping/ }.should_not be_empty
end

Then /^an SMS notification for entity '([\w\.\-]+)' should not be queued for the user$/ do |entity|
  queue = ResqueSpec.peek('sms_notifications')
  queue.select {|n| n[:args].first['event_id'] =~ /#{entity}:ping/ }.should be_empty
end

Then /^an email notification for entity '([\w\.\-]+)' should not be queued for the user$/ do |entity|
  queue = ResqueSpec.peek('email_notifications')
  queue.select {|n| n[:args].first['event_id'] =~ /#{entity}:ping/ }.should be_empty
end

Given /^a user SMS notification has been queued for entity '([\w\.\-]+)'$/ do |entity|
  add_entity( 'id'       => '5000',
              'name'     => entity )
  @sms_notification = {'notification_type'  => 'problem',
                       'contact_first_name' => 'John',
                       'contact_last_name'  => 'Smith',
                       'state'              => 'CRITICAL',
                       'summary'            => 'Socket timeout after 10 seconds',
                       'time'               => Time.now.to_i,
                       'event_id'           => "#{entity}:ping",
                       'address'            => '+61412345678',
                       'id'                 => 1}
end

Given /^a user email notification has been queued for entity '([\w\.\-]+)'$/ do |entity|
  add_entity( 'id'       => '5001',
              'name'     => entity )
  @email_notification = {'notification_type'  => 'problem',
                         'contact_first_name' => 'John',
                         'contact_last_name'  => 'Smith',
                         'state'              => 'CRITICAL',
                         'summary'            => 'Socket timeout after 10 seconds',
                         'time'               => Time.now.to_i,
                         'event_id'           => "#{entity}:ping",
                         'address'            => 'johns@example.dom',
                         'id'                 => 2}
end

# NB using perform, the notifiers were accessing the wrong Redis DB number

# TODO may need to get more complex, depending which SMS provider is used
When /^the SMS notification handler runs successfully$/ do
  # returns success by default - currently matches all addresses, maybe load from config?
  stub_request(:get, /.*/)
  # TODO load config from cfg file instead?
  Flapjack::Notification::Sms.class_variable_set('@@config', {'username' => 'abcd', 'password' => 'efgh'})

  lambda {
    Flapjack::Notification::Sms.dispatch(@sms_notification, :logger => @logger, :redis => @redis)
  }.should_not raise_error
  @sms_sent = true
end

When /^the SMS notification handler fails to send an SMS$/ do
  stub_request(:any, /.*/).to_return(:status => [500, "Internal Server Error"])

  lambda {
    Flapjack::Notification::Sms.dispatch(@sms_notification, :logger => @logger, :redis => @redis)
  }.should raise_error
  @sms_sent = false
end

When /^the email notification handler runs successfully$/ do
  lambda {
    Flapjack::Notification::Email.dispatch(@email_notification, :logger => @logger, :redis => @redis)
  }.should_not raise_error
end

# This doesn't work as I have it here -- sends a mail with an empty To: header instead.
# Might have to introduce Rspec's stubs here to fake bad mailer behaviour -- or if mail sending
# won't ever fail, don't test for failure?
When /^the email notification handler fails to send an email$/ do
  pending
  lambda {
    @email_notification['address'] = nil
    Flapjack::Notification::Email.dispatch(@email_notification, :logger => @logger, :redis => @redis)
  }.should_not raise_error
end

Then /^the user should receive an SMS notification$/ do
  @sms_sent.should be_true
end

Then /^the user should receive an email notification$/ do
  have_sent_email.should be_true
end

Then /^the user should not receive an SMS notification$/ do
  @sms_sent.should be_false
end

Then /^the user should not receive an email notification$/ do
  have_sent_email.should be_false
end
