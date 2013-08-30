
require 'flapjack/gateways/email'
require 'flapjack/gateways/sms_messagenet'

# copied from flapjack-populator
# TODO use Flapjack::Data::Contact.add
def add_contact(contact = {})
  Flapjack.redis.multi
  Flapjack.redis.del("contact:#{contact['id']}")
  Flapjack.redis.del("contact_media:#{contact['id']}")
  Flapjack.redis.hset("contact:#{contact['id']}", 'first_name', contact['first_name'])
  Flapjack.redis.hset("contact:#{contact['id']}", 'last_name',  contact['last_name'])
  Flapjack.redis.hset("contact:#{contact['id']}", 'email',      contact['email'])
  contact['media'].each_pair {|medium, address|
    Flapjack.redis.hset("contact_media:#{contact['id']}", medium, address)
  }
  Flapjack.redis.exec
end

Given /^the user wants to receive SMS notifications for entity '([\w\.\-]+)'$/ do |entity|
  add_contact( 'id'         => '0999',
               'first_name' => 'John',
               'last_name'  => 'Smith',
               'email'      => 'johns@example.dom',
               'media'      => {'sms' => '+61888888888'} )
  Flapjack::Data::Entity.add({'id'       => '5000',
                              'name'     => entity,
                              'contacts' => ["0999"]})
end

Given /^the user wants to receive email notifications for entity '([\w\.\-]+)'$/ do |entity|
  add_contact( 'id'         => '0999',
               'first_name' => 'John',
               'last_name'  => 'Smith',
               'email'      => 'johns@example.dom',
               'media'      => {'email' => 'johns@example.dom'} )
  Flapjack::Data::Entity.add({'id'       => '5000',
                              'name'     => entity,
                              'contacts' => ["0999"]})
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
                              'contacts' => ["0998"]})
  Flapjack::Data::Entity.add({'id'       => '5001',
                              'name'     => entity2,
                              'contacts' => ["0999"]})
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

  entity_check = Flapjack::Data::EntityCheck.for_entity_name(entity, 'ping')
  max_notified_severity = entity_check.max_notified_severity_of_current_failure

  severity = Flapjack::Data::Notification.severity_for_event(event, max_notified_severity)
  last_state = entity_check.historical_state_before(event.time)

  Flapjack::Data::Notification.push('notifications', event,
    :type => notification_type, :severity => severity,
    :last_state => last_state)
  drain_notifications
end

Then /^an SMS notification for entity '([\w\.\-]+)' should be queued for the user$/ do |entity|
  queue = redis_peek('sms_notifications')
  queue.select {|n| n['event_id'] =~ /#{entity}:ping/ }.should_not be_empty
end

Then /^an email notification for entity '([\w\.\-]+)' should be queued for the user$/ do |entity|
  queue = redis_peek('email_notifications')
  queue.select {|n| n['event_id'] =~ /#{entity}:ping/ }.should_not be_empty
end

Then /^an SMS notification for entity '([\w\.\-]+)' should not be queued for the user$/ do |entity|
  queue = redis_peek('sms_notifications')
  queue.select {|n| n['event_id'] =~ /#{entity}:ping/ }.should be_empty
end

Then /^an email notification for entity '([\w\.\-]+)' should not be queued for the user$/ do |entity|
  queue = redis_peek('email_notifications')
  queue.select {|n| n['event_id'] =~ /#{entity}:ping/ }.should be_empty
end

Given /^a user SMS notification has been queued for entity '([\w\.\-]+)'$/ do |entity|
  Flapjack::Data::Entity.add({'id'   => '5000',
                              'name' => entity})
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
                              'name' => entity})
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

# TODO may need to get more complex, depending which SMS provider is used
When /^the SMS notification handler runs successfully$/ do
  @request = stub_request(:get, /^#{Regexp.escape('https://www.messagenet.com.au/dotnet/Lodge.asmx/LodgeSMSMessage')}/)

  @sms = Flapjack::Gateways::SmsMessagenet.new(:config => {'username' => 'abcd', 'password' => 'efgh'}, :logger => @logger )
  @sms.handle_message(@sms_notification)
end

When /^the SMS notification handler fails to send an SMS$/ do
  @request = stub_request(:get, /^#{Regexp.escape('https://www.messagenet.com.au/dotnet/Lodge.asmx/LodgeSMSMessage')}/).to_return(:status => [500, "Internal Server Error"])

  @sms = Flapjack::Gateways::SmsMessagenet.new(:config => {'username' => 'abcd', 'password' => 'efgh'}, :logger => @logger )
  @sms.handle_message(@sms_notification)
end

When /^the email notification handler runs successfully$/ do
  @email = Flapjack::Gateways::Email.new(:config => {'smtp_config' => {'host' => '127.0.0.1', 'port' => 2525}}, :logger => @logger)
  @email.handle_message(@email_notification)
end

When /^the email notification handler fails to send an email$/ do
  module Mail
    class TestMailer
      alias_method :"orig_deliver!", :"deliver!"
      def deliver!(mail); raise RuntimeError.new; end
    end
  end

  @email = Flapjack::Gateways::Email.new(:config => {'smtp_config' => {'host' => '127.0.0.1', 'port' => 2525}}, :logger => @logger)
  begin
    @email.handle_message(@email_notification)
  rescue RuntimeError
  end

  module Mail
    class TestMailer
      alias_method :"deliver!", :"orig_deliver!"
    end
  end
end

Then /^the user should receive an SMS notification$/ do
  @request.should have_been_requested
  @sms.sent.should == 1
end

Then /^the user should receive an email notification$/ do
  Mail::TestMailer.deliveries.length.should == 1
  @email.sent.should == 1
end

Then /^the user should not receive an SMS notification$/ do
  @request.should have_been_requested
  @sms.sent.should == 0
end

Then /^the user should not receive an email notification$/ do
  Mail::TestMailer.deliveries.should be_empty
  @email.sent.should == 0
end
