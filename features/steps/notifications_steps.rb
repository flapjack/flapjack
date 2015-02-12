
# copied from flapjack-populator
# TODO use Flapjack::Data::Contact.add
def add_contact(contact = {})
  @notifier_redis.multi do |multi|
    multi.del("contact:#{contact['id']}")
    multi.del("contact_media:#{contact['id']}")
    multi.hset("contact:#{contact['id']}", 'first_name', contact['first_name'])
    multi.hset("contact:#{contact['id']}", 'last_name',  contact['last_name'])
    multi.hset("contact:#{contact['id']}", 'email',      contact['email'])
    contact['media'].each_pair {|medium, address|
      multi.hset("contact_media:#{contact['id']}", medium, address)
    }
  end
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
                             :redis => @notifier_redis )
end

Given /^the user wants to receive Nexmo SMS notifications for entity '([\w\.\-]+)'$/ do |entity|
  add_contact( 'id'         => '0999',
               'first_name' => 'John',
               'last_name'  => 'Smith',
               'email'      => 'johns@example.dom',
               'media'      => {'sms_nexmo' => '+61888888888'} )
  Flapjack::Data::Entity.add({'id'       => '5000',
                              'name'     => entity,
                              'contacts' => ["0999"]},
                             :redis => @notifier_redis )
end

Given /^the user wants to receive SNS notifications for entity '([\w\.\-]+)'$/ do |entity|
  add_contact( 'id'         => '0999',
               'first_name' => 'John',
               'last_name'  => 'Smith',
               'email'      => 'johns@example.dom',
               'media'      => {'sns' => 'arn:aws:sns:us-east-1:698519295917:My-Topic'} )
  Flapjack::Data::Entity.add({'id'       => '5000',
                              'name'     => entity,
                              'contacts' => ["0999"]},
                              :redis => @notifier_redis )
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
                             :redis => @notifier_redis )
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
                             :redis => @notifier_redis )
  Flapjack::Data::Entity.add({'id'       => '5001',
                              'name'     => entity2,
                              'contacts' => ["0999"]},
                             :redis => @notifier_redis )
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
    :redis => @notifier_redis)
  drain_notifications
end

Then /^an SMS notification for entity '([\w\.\-]+)' should be queued for the user$/ do |entity|
  queue = redis_peek('sms_notifications')
  expect(queue.select {|n| n['event_id'] =~ /#{entity}:ping/ }).not_to be_empty
end

Then /^a Nexmo SMS notification for entity '([\w\.\-]+)' should be queued for the user$/ do |entity|
  queue = redis_peek('sms_nexmo_notifications')
  expect(queue.select {|n| n['event_id'] =~ /#{entity}:ping/ }).not_to be_empty
end

Then /^an SNS notification for entity '([\w\.\-]+)' should be queued for the user$/ do |entity|
  queue = redis_peek('sns_notifications')
  expect(queue.select {|n| n['event_id'] =~ /#{entity}:ping/ }).not_to be_empty
end

Then /^an email notification for entity '([\w\.\-]+)' should be queued for the user$/ do |entity|
  queue = redis_peek('email_notifications')
  expect(queue.select {|n| n['event_id'] =~ /#{entity}:ping/ }).not_to be_empty
end

Then /^an SMS notification for entity '([\w\.\-]+)' should not be queued for the user$/ do |entity|
  queue = redis_peek('sms_notifications')
  expect(queue.select {|n| n['event_id'] =~ /#{entity}:ping/ }).to be_empty
end

Then /^an Nexmo SMS notification for entity '([\w\.\-]+)' should not be queued for the user$/ do |entity|
  queue = redis_peek('sms_nexmo_notifications')
  expect(queue.select {|n| n['event_id'] =~ /#{entity}:ping/ }).to be_empty
end

Then /^an email notification for entity '([\w\.\-]+)' should not be queued for the user$/ do |entity|
  queue = redis_peek('email_notifications')
  expect(queue.select {|n| n['event_id'] =~ /#{entity}:ping/ }).to be_empty
end

Given /^a user SMS notification has been queued for entity '([\w\.\-]+)'$/ do |entity|
  Flapjack::Data::Entity.add({'id'   => '5000',
                              'name' => entity},
                             :redis => @redis )
  @sms_notification = {'notification_type'  => 'problem',
                       'contact_first_name' => 'John',
                       'contact_last_name'  => 'Smith',
                       'state'              => 'critical',
                       'summary'            => 'Socket timeout after 10 seconds',
                       'time'               => Time.now.to_i,
                       'event_id'           => "#{entity}:ping",
                       'address'            => '+61412345678',
                       'id'                 => 1,
                       'state_duration'     => 30,
                       'duration'           => 45}

  Flapjack::Data::Alert.add('sms_notifications', @sms_notification,
                            :redis => @notifier_redis)
end

Given /^a user Nexmo SMS notification has been queued for entity '([\w\.\-]+)'$/ do |entity|
  Flapjack::Data::Entity.add({'id'   => '5000',
                              'name' => entity},
                             :redis => @redis )
  @sms_nexmo_notification = {'notification_type'  => 'problem',
                       'contact_first_name' => 'John',
                       'contact_last_name'  => 'Smith',
                       'state'              => 'critical',
                       'summary'            => 'Socket timeout after 10 seconds',
                       'time'               => Time.now.to_i,
                       'event_id'           => "#{entity}:ping",
                       'address'            => '+61412345678',
                       'id'                 => 1,
                       'state_duration'     => 30,
                       'duration'           => 45}

  Flapjack::Data::Alert.add('sms_nexmo_notifications', @sms_nexmo_notification,
                            :redis => @notifier_redis)
end

Given /^a user SNS notification has been queued for entity '([\w\.\-]+)'$/ do |entity|
  Flapjack::Data::Entity.add({'id'   => '5000',
                              'name' => entity},
                             :redis => @redis )
  @sns_notification = {'notification_type'  => 'problem',
                       'contact_first_name' => 'John',
                       'contact_last_name'  => 'Smith',
                       'state'              => 'critical',
                       'summary'            => 'Socket timeout after 10 seconds',
                       'time'               => Time.now.to_i,
                       'event_id'           => "#{entity}:ping",
                       'address'            => 'arn:aws:sns:us-east-1:698519295917:My-Topic',
                       'id'                 => 1,
                       'state_duration'     => 30,
                       'duration'           => 45}

  Flapjack::Data::Alert.add('sns_notifications', @sns_notification,
                            :redis => @notifier_redis)
end

Given /^a user email notification has been queued for entity '([\w\.\-]+)'$/ do |entity|
  Flapjack::Data::Entity.add({'id'   => '5001',
                              'name' => entity},
                             :redis => @redis )
  @email_notification = {'notification_type'  => 'problem',
                         'contact_first_name' => 'John',
                         'contact_last_name'  => 'Smith',
                         'state'              => 'critical',
                         'summary'            => 'Socket timeout after 10 seconds',
                         'time'               => Time.now.to_i,
                         'event_id'           => "#{entity}:ping",
                         'address'            => 'johns@example.dom',
                         'id'                 => 2,
                         'state_duration'     => 30,
                         'duration'           => 3600}

  Flapjack::Data::Alert.add('email_notifications', @email_notification,
                            :redis => @notifier_redis)
end

When /^the SMS notification handler runs successfully$/ do
  @request = stub_request(:get, /^#{Regexp.escape(Flapjack::Gateways::SmsMessagenet::MESSAGENET_DEFAULT_URL)}/)

  @sms_messagenet = Flapjack::Gateways::SmsMessagenet.new(:config => {
      'username' => 'abcd', 'password' => 'efgh'
    }, :redis_config => @redis_opts, :logger => @logger)

  drain_alerts('sms_notifications', @sms_messagenet)
end

When /^the Nexmo SMS notification handler runs successfully$/ do
  # poor man's stubbing
  Nexmo::Client.class_eval {
    def send_message(args = {})
    end
  }
  @sms_nexmo = Flapjack::Gateways::SmsNexmo.new(:config => {
      'api_key' => 'THEAPIKEY', 'secret' => 'secret', 'from' => 'someone',
    }, :redis_config => @redis_opts, :logger => @logger)

  drain_alerts('sms_nexmo_notifications', @sms_nexmo)
end

When /^the SNS notification handler runs successfully$/ do
  @request = stub_request(:post, /amazonaws\.com/)

  @aws_sns = Flapjack::Gateways::AwsSns.new(:config => {
    'access_key' => "AKIAIOSFODNN7EXAMPLE",
    'secret_key' => "secret"
  }, :redis_config => @redis_opts, :logger => @logger)

  drain_alerts('sns_notifications', @aws_sns)
end

When /^the SMS notification handler fails to send an SMS$/ do
  @request = stub_request(:get, /^#{Regexp.escape(Flapjack::Gateways::SmsMessagenet::MESSAGENET_DEFAULT_URL)}/).to_return(:status => [500, "Internal Server Error"])

  @sms_messagenet = Flapjack::Gateways::SmsMessagenet.new(:config => {
      'username' => 'abcd', 'password' => 'efgh'
    }, :redis_config => @redis_opts, :logger => @logger)

  drain_alerts('sms_notifications', @sms_messagenet)
end

When /^the SNS notification handler fails to send an SMS$/ do
  @request = stub_request(:post, /amazonaws\.com/).to_return(:status => [500, "Internal Server Error"])

  @aws_sns = Flapjack::Gateways::AwsSns.new(:config => {
    'access_key' => "AKIAIOSFODNN7EXAMPLE",
    'secret_key' => "secret"
  }, :redis_config => @redis_opts, :logger => @logger)

  drain_alerts('sns_notifications', @aws_sns)
end

When /^the email notification handler runs successfully$/ do
  # poor man's stubbing
  EM::P::SmtpClient.class_eval {
    def self.send(args = {})
      me = MockEmailer.new
      me.set_deferred_status :succeeded, OpenStruct.new(:code => 250)
      me
    end
  }

  @email = Flapjack::Gateways::Email.new(:config => {
    'smtp_config' => {'host' => '127.0.0.1',
                      'port' => 2525,
                      'from' => 'flapjack@example'}
  }, :redis_config => @redis_opts, :logger => @logger)

  drain_alerts('email_notifications', @email)
end

When /^the email notification handler fails to send an email$/ do
  # poor man's stubbing
  EM::P::SmtpClient.class_eval {
    def self.send(args = {})
      me = MockEmailer.new
      me.set_deferred_status :failed, OpenStruct.new(:code => 500)
      me
    end
  }

  @email = Flapjack::Gateways::Email.new(:config => {
    'smtp_config' => {'host' => '127.0.0.1',
                      'port' => 2525,
                      'from' => 'flapjack@example'}
  }, :redis_config => @redis_opts, :logger => @logger)

  drain_alerts('email_notifications', @email)
end

Then /^the user should( not)? receive an SMS notification$/ do |negativity|
  expect(@request).to have_been_requested
  expect(@sms_messagenet.instance_variable_get('@sent')).to eq(negativity.nil? ? 1 : 0)
end

Then /^the user should( not)? receive an Nexmo SMS notification$/ do |negativity|
  expect(@sms_nexmo.instance_variable_get('@sent')).to eq(negativity.nil? ? 1 : 0)
end

Then /^the user should( not)? receive an SNS notification$/ do |negativity|
  expect(@request).to have_been_requested
  expect(@aws_sns.instance_variable_get('@sent')).to eq(negativity.nil? ? 1 : 0)
end

Then /^the user should( not)? receive an email notification$/ do |negativity|
  expect(@email.instance_variable_get('@sent')).to eq(negativity.nil? ? 1 : 0)
end

