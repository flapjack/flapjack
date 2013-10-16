
# copied from flapjack-populator
# TODO use Flapjack::Data::Contact.add
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
  Flapjack::Data::Entity.add({'id'       => '5000',
                              'name'     => entity,
                              'contacts' => ["0999"]},
                             :redis => @redis )
end

Given /^the user wants to receive email notifications for entity '([\w\.\-]+)'$/ do |entity|
  add_contact( 'id'         => '0999',
               'first_name' => 'John',
               'last_name'  => 'Smith',
               'email'      => 'johns@example.dom',
               'media'      => {'email' => 'johns@example.dom'} )
  Flapjack::Data::Entity.add({'id'       => '5000',
                              'name'     => entity,
                              'contacts' => ["0999"]},
                             :redis => @redis )
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
  Flapjack::Data::Entity.add({'id'       => '5000',
                              'name'     => entity1,
                              'contacts' => ["0998"]},
                             :redis => @redis )
  Flapjack::Data::Entity.add({'id'       => '5001',
                              'name'     => entity2,
                              'contacts' => ["0999"]},
                             :redis => @redis )
end

# TODO create the notification object in redis, flag the relevant operation as
# only needing that part running, split up the before block that covers these
When /^an event notification is generated for entity '([\w\.\-]+)'$/ do |entity|
  event = Flapjack::Data::Event.new('type'    => 'service',
                                    'state'   => 'critical',
                                    'summary' => '100% packet loss',
                                    'entity'  => entity,
                                    'check'   => 'ping')

  notification_type = Flapjack::Data::Notification.type_for_event(event)

  entity_check = Flapjack::Data::EntityCheck.for_entity_name(entity, 'ping', :redis => @redis)
  max_notified_severity = entity_check.max_notified_severity_of_current_failure

  severity = Flapjack::Data::Notification.severity_for_event(event, max_notified_severity)
  last_state = entity_check.historical_state_before(event.time)

  Flapjack::Data::Notification.add('notifications', event,
    :type => notification_type, :severity => severity, :last_state => last_state,
    :redis => @redis)
  drain_notifications
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
  Flapjack::Data::Entity.add({'id'   => '5000',
                              'name' => entity},
                             :redis => @redis )
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
  Flapjack::Data::Entity.add({'id'   => '5001',
                              'name' => entity},
                             :redis => @redis )
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
  @request = stub_request(:get, /^#{Regexp.escape(Flapjack::Gateways::SmsMessagenet::MESSAGENET_DEFAULT_URL)}/)

  Flapjack::Gateways::SmsMessagenet.instance_variable_set('@config', {'username' => 'abcd', 'password' => 'efgh'})
  Flapjack::Gateways::SmsMessagenet.instance_variable_set('@redis', @redis)
  Flapjack::Gateways::SmsMessagenet.instance_variable_set('@logger', @logger)
  Flapjack::Gateways::SmsMessagenet.start

  Flapjack::Gateways::SmsMessagenet.perform(@sms_notification)
end

When /^the SMS notification handler fails to send an SMS$/ do
  @request = stub_request(:get, /^#{Regexp.escape(Flapjack::Gateways::SmsMessagenet::MESSAGENET_DEFAULT_URL)}/).to_return(:status => [500, "Internal Server Error"])
  Flapjack::Gateways::SmsMessagenet.instance_variable_set('@config', {'username' => 'abcd', 'password' => 'efgh'})
  Flapjack::Gateways::SmsMessagenet.instance_variable_set('@redis', @redis)
  Flapjack::Gateways::SmsMessagenet.instance_variable_set('@logger', @logger)
  Flapjack::Gateways::SmsMessagenet.start

  Flapjack::Gateways::SmsMessagenet.perform(@sms_notification)
end

When /^the email notification handler runs successfully$/ do
  Resque.redis = @redis
  Flapjack::Gateways::Email.instance_variable_set('@config', {'smtp_config' => {'host' => '127.0.0.1', 'port' => 2525}})
  Flapjack::Gateways::Email.instance_variable_set('@redis', @redis)
  Flapjack::Gateways::Email.instance_variable_set('@logger', @logger)
  Flapjack::Gateways::Email.start

  # poor man's stubbing
  EM::P::SmtpClient.class_eval {
    def self.send(args = {})
      me = MockEmailer.new
      me.set_deferred_status :succeeded, OpenStruct.new(:code => 250)
      me
    end
  }

  Flapjack::Gateways::Email.perform(@email_notification)
end

When /^the email notification handler fails to send an email$/ do
  Resque.redis = @redis
  Flapjack::Gateways::Email.instance_variable_set('@config', {'smtp_config' => {'host' => '127.0.0.1', 'port' => 2525}})
  Flapjack::Gateways::Email.instance_variable_set('@redis', @redis)
  Flapjack::Gateways::Email.instance_variable_set('@logger', @logger)
  Flapjack::Gateways::Email.start

  # poor man's stubbing
  EM::P::SmtpClient.class_eval {
    def self.send(args = {})
      me = MockEmailer.new
      me.set_deferred_status :failed, OpenStruct.new(:code => 500)
      me
    end
  }

  Flapjack::Gateways::Email.perform(@email_notification)
end

Then /^the user should receive an SMS notification$/ do
  @request.should have_been_requested
  Flapjack::Gateways::SmsMessagenet.instance_variable_get('@sent').should == 1
end

Then /^the user should receive an email notification$/ do
  Flapjack::Gateways::Email.instance_variable_get('@sent').should == 1
end

Then /^the user should not receive an SMS notification$/ do
  @request.should have_been_requested
  Flapjack::Gateways::SmsMessagenet.instance_variable_get('@sent').should == 0
end

Then /^the user should not receive an email notification$/ do
  Flapjack::Gateways::Email.instance_variable_get('@sent').should == 0
end
