
require 'flapjack/gateways/email'
require 'flapjack/gateways/sms_messagenet'

def find_or_create_contact(contact_data)
  contact = Flapjack::Data::Contact.find_by_id(contact_data['id'])
  if contact.nil?
    contact = Flapjack::Data::Contact.new(:id => contact_data['id'],
      :first_name => contact_data['first_name'],
      :last_name => contact_data['last_name'],
      :email => contact_data['email'])
    contact.save.should be_true
  end

  if contact_data['media']
    contact_data['media'].each_pair {|type, address|
      medium = Flapjack::Data::Medium.new(:type => type, :address => address, :interval => 600)
      medium.save.should be_true
      contact.media << medium
    }
  end

  contact
end

def find_or_create_entity(entity_data)
  entity = Flapjack::Data::Entity.find_by_id(entity_data['id'])
  if entity.nil?
    entity = Flapjack::Data::Entity.new(:id => entity_data['id'],
      :name => entity_data['name'])
    entity.save.should be_true

    entity_check = Flapjack::Data::Check.new(:entity_name => entity.name, :name => 'ping')
    entity_check.save.should be_true

    entity.checks << entity_check
  end

  entity
end

Given /^(?:a|the) user wants to receive SMS notifications for entity '([\w\.\-]+)'$/ do |entity_name|
  contact = find_or_create_contact( 'id'         => '0999',
                                    'first_name' => 'John',
                                    'last_name'  => 'Smith',
                                    'email'      => 'johns@example.dom',
                                    'media'      => {'sms' => '+61888888888'} )
  entity = find_or_create_entity('id'       => '5000',
                                 'name'     => entity_name)
  entity.contacts << contact
end

Given /^(?:a|the) user wants to receive email notifications for entity '([\w\.\-]+)'$/ do |entity_name|
  contact = find_or_create_contact( 'id'         => '1000',
                                    'first_name' => 'Jane',
                                    'last_name'  => 'Smith',
                                    'email'      => 'janes@example.dom',
                                    'media'      => {'email' => 'janes@example.dom'} )

  entity = find_or_create_entity('id'       => '5001',
                                 'name'     => entity_name)
  entity.contacts << contact
end

# TODO create the notification object in redis, flag the relevant operation as
# only needing that part running, split up the before block that covers these
When /^an event notification is generated for entity '([\w\.\-]+)'$/ do |entity_name|
  timestamp = Time.now.to_i

  event = Flapjack::Data::Event.new('type'    => 'service',
                                    'state'   => 'critical',
                                    'summary' => '100% packet loss',
                                    'entity'  => entity_name,
                                    'check'   => 'ping',
                                    'time'    => timestamp)

  entity_check = Flapjack::Data::Check.intersect(:entity_name => entity_name,
    :name => 'ping').all.first
  entity_check.should_not be_nil
  entity_check.state = 'critical'
  entity_check.last_update = timestamp
  entity_check.save.should be_true

  max_notified_severity = entity_check.max_notified_severity_of_current_failure
  severity = Flapjack::Data::Notification.severity_for_state(event.state,
               max_notified_severity)

  current_state = entity_check.states.last
  previous_state = entity_check.states.intersect_range(-2, -1).first

  notification = Flapjack::Data::Notification.new(
    :entity_check_id   => entity_check.id,
    :state_id          => current_state.id,
    :state_duration    => 0,
    :previous_state_id => (previous_state ? previous_state.id : nil),
    :severity          => severity,
    :type              => event.notification_type,
    :time              => event.time,
    :duration          => event.duration,
    :tags              => entity_check.tags,
  )

  Flapjack::Data::Notification.push('notifications', notification)
  drain_notifications
end

Then /^an (SMS|email) notification for entity '([\w\.\-]+)' should( not)? be queued$/ do |medium, entity_name, neg|
  queue = redis_peek("#{medium.downcase}_notifications")
  queue.select {|n| n['entity'] =~ /#{entity_name}/ }.
        send((neg ? :should : :should_not), be_empty)
end

Given /^an SMS notification has been queued for entity '([\w\.\-]+)'$/ do |entity_name|
  entity = find_or_create_entity('id'       => '5001',
                                 'name'     => entity_name)

  @sms_notification = {'notification_type'  => 'problem',
                       'contact_first_name' => 'John',
                       'contact_last_name'  => 'Smith',
                       'state'              => 'CRITICAL',
                       'summary'            => 'Socket timeout after 10 seconds',
                       'time'               => Time.now.to_i,
                       'entity'             => entity_name,
                       'check'              => "ping",
                       'address'            => '+61412345678',
                       'id'                 => 1}
end

Given /^an email notification has been queued for entity '([\w\.\-]+)'$/ do |entity_name|
  entity = find_or_create_entity('id'       => '5001',
                                 'name'     => entity_name)

  entity_check = Flapjack::Data::Check.intersect(:entity_name => entity_name,
    :name => 'ping').all.first
  entity_check.should_not be_nil

  @email_notification = {'notification_type'  => 'problem',
                         'contact_first_name' => 'John',
                         'contact_last_name'  => 'Smith',
                         'state'              => 'CRITICAL',
                         'summary'            => 'Socket timeout after 10 seconds',
                         'time'               => Time.now.to_i,
                         'entity'             => entity_name,
                         'check'              => "ping",
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
