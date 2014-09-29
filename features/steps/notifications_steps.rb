require 'flapjack/gateways/aws_sns'
require 'flapjack/gateways/email'
require 'flapjack/gateways/sms_messagenet'

def find_or_create_contact(contact_data)
  contact = Flapjack::Data::Contact.find_by_id(contact_data['id'])
  if contact.nil?
    contact = Flapjack::Data::Contact.new(:id => contact_data['id'],
      :first_name => contact_data['first_name'],
      :last_name => contact_data['last_name'],
      :email => contact_data['email'])
    expect(contact.save).to be true
  end

  if contact_data['media']
    contact_data['media'].each_pair {|type, address|
      medium = Flapjack::Data::Medium.new(:type => type, :address => address, :interval => 600)
      expect(medium.save).to be true
      contact.media << medium
    }
  end

  contact
end

def find_or_create_check(check_data)
  check = Flapjack::Data::Check.find_by_id(check_data['id'])

  if check.nil?
    check = Flapjack::Data::Check.new(:id => check_data['id'],
      :name => check_data['name'])
    expect(check.save).to be true

    entity_name, check_name = check_data['name'].split(':', 2)

    tags = entity_name.split('.', 2).map(&:downcase) +
      check_name.split(' ').map(&:downcase)

    tags.each do |tag_name|
      tag = Flapjack::Data::Tag.intersect(:name => tag_name).all.first
      if tag.nil?
        tag = Flapjack::Data::Tag.new(:name => tag_name)
        expect(tag.save).to be true
      end
      check.tags << tag
    end
  end

  check
end

Given /^(?:a|the) user wants to receive SMS notifications for check '(.+)'$/ do |check_name|
  contact = find_or_create_contact( 'id'         => '0999',
                                    'first_name' => 'John',
                                    'last_name'  => 'Smith',
                                    'email'      => 'johns@example.dom',
                                    'media'      => {'sms' => '+61888888888'} )
  check = find_or_create_check('id'   => '5000',
                               'name' => check_name)
  check.contacts << contact
end

Given /^(?:a|the) user wants to receive email notifications for check '(.+)'$/ do |check_name|
  contact = find_or_create_contact( 'id'         => '1000',
                                    'first_name' => 'Jane',
                                    'last_name'  => 'Smith',
                                    'email'      => 'janes@example.dom',
                                    'media'      => {'email' => 'janes@example.dom'} )

  check = find_or_create_check('id'   => '5001',
                               'name' => check_name)
  check.contacts << contact
end

Given /^(?:a|the) user wants to receive SNS notifications for check '(.+)'$/ do |check_name|
  contact = find_or_create_contact( 'id'         => '1001',
                                    'first_name' => 'James',
                                    'last_name'  => 'Smithson',
                                    'email'      => 'jamess@example.dom',
                                    'media' => {'sns' => 'arn:aws:sns:us-east-1:698519295917:My-Topic'} )
  check = find_or_create_check('id'       => '5002',
                               'name'     => check_name)
  check.contacts << contact
end

# TODO create the notification object in redis, flag the relevant operation as
# only needing that part running, split up the before block that covers these
When /^an event notification is generated for check '(.+)'$/ do |check_name|
  timestamp = Time.now.to_i

  event = Flapjack::Data::Event.new('type'    => 'service',
                                    'state'   => 'critical',
                                    'summary' => '100% packet loss',
                                    'check'   => check_name.split(':', 2).first,
                                    'check'   => check_name.split(':', 2).last,
                                    'time'    => timestamp)

  check = Flapjack::Data::Check.intersect(:name => check_name).all.first
  expect(check).not_to be_nil

  check.state = 'critical'
  check.last_update = timestamp
  expect(check.save).to be true

  max_notified_severity = check.max_notified_severity_of_current_failure
  severity = Flapjack::Data::Notification.severity_for_state(event.state,
               max_notified_severity)

  current_state = check.states.last
  previous_state = check.states.intersect_range(-2, -1).first

  notification = Flapjack::Data::Notification.new(
    :state_duration    => 0,
    :severity          => severity,
    :type              => event.notification_type,
    :time              => event.time,
    :duration          => event.duration,
  )

  unless notification.save
    raise "Couldn't save notification: #{@notification.errors.full_messages.inspect}"
  end

  notification.tags.add(*check.tags.all) unless check.tags.empty?

  check.notifications << notification
  current_state.current_notifications << notification
  previous_state.previous_notifications << notification

  @notifier.instance_variable_get('@queue').push(notification)
  drain_notifications
end

Then /^an (SMS|SNS|email) notification for check '(.+)' should( not)? be queued$/ do |medium, check_name, neg|
  queue = redis_peek("#{medium.downcase}_notifications", Flapjack::Data::Alert)
  expect(queue.select {|n| n.check.name == check_name }).
        send((neg ? :to : :not_to), be_empty)
end

Given /^an (SMS|SNS|email) notification has been queued for check '(.+)'$/ do |media_type, check_name|
  check = Flapjack::Data::Check.intersect(:name => check_name).all.first
  expect(check).not_to be_nil

  check.state = 'critical'
  check.last_update = Time.now.to_i
  expect(check.save).to be true

  @alert = Flapjack::Data::Alert.new(
    :state => check.states.all.last.state,
    :rollup => nil,
    :state_duration => 15,
    :notification_type => 'problem',
    :time => Time.now)

  unless @alert.save
    raise "Couldn't save alert: #{@alert.errors.full_messages.inspect}"
  end

  contact = check.contacts.all.first
  expect(contact).not_to be_nil

  medium = contact.media.intersect(:type => media_type.downcase).all.first
  expect(medium).not_to be_nil

  medium.alerts << @alert
  check.alerts << @alert
end

# TODO may need to get more complex, depending which SMS provider is used
When /^the SMS notification handler runs successfully$/ do
  @request = stub_request(:get, /^#{Regexp.escape('https://www.messagenet.com.au/dotnet/Lodge.asmx/LodgeSMSMessage')}/)
  @sms = Flapjack::Gateways::SmsMessagenet.new(:config => {'username' => 'abcd', 'password' => 'efgh'}, :logger => @logger )
  @sms.send(:handle_alert, @alert)
end

When /^the SMS notification handler fails to send an SMS$/ do
  @request = stub_request(:get, /^#{Regexp.escape('https://www.messagenet.com.au/dotnet/Lodge.asmx/LodgeSMSMessage')}/).to_return(:status => [500, "Internal Server Error"])
  @sms = Flapjack::Gateways::SmsMessagenet.new(:config => {'username' => 'abcd', 'password' => 'efgh'}, :logger => @logger )
  @sms.send(:handle_alert, @alert)
end

When /^the email notification handler runs successfully$/ do
  @email = Flapjack::Gateways::Email.new(:config => {'smtp_config' => {'host' => '127.0.0.1', 'port' => 2525, 'from' => 'flapjack@example.com'}}, :logger => @logger)
  @email.send(:handle_alert, @alert)
end

When /^the email notification handler fails to send an email$/ do
  module Mail
    class TestMailer
      alias_method :"orig_deliver!", :"deliver!"
      def deliver!(mail); raise RuntimeError.new; end
    end
  end

  @email = Flapjack::Gateways::Email.new(:config => {'smtp_config' => {'host' => '127.0.0.1', 'port' => 2525, 'from' => 'flapjack@example.com'}}, :logger => @logger)
  begin
    @email.send(:handle_alert, @alert)
  rescue RuntimeError
  end

  module Mail
    class TestMailer
      alias_method :"deliver!", :"orig_deliver!"
    end
  end
end

When /^the SNS notification handler runs successfully$/ do
  @request = stub_request(:post, /amazonaws\.com/)
  @sns = Flapjack::Gateways::AwsSns.new(:config => {
    'access_key' => "AKIAIOSFODNN7EXAMPLE",
    'secret_key' => "secret"}, :logger => @logger)
  @sns.send(:handle_alert, @alert)
end

When /^the SNS notification handler fails to send an SMS$/ do
  @request = stub_request(:post, /amazonaws\.com/).to_return(:status => [500, "Internal Server Error"])
  @sns = Flapjack::Gateways::AwsSns.new(:config => {
    'access_key' => "AKIAIOSFODNN7EXAMPLE",
    'secret_key' => "secret"}, :logger => @logger)
  @sns.send(:handle_alert, @alert)
end

Then /^the user should receive an SMS notification$/ do
  expect(@request).to have_been_requested
  expect(@sms.sent).to eq(1)
end

Then /^the user should receive an SNS notification$/ do
  expect(@request).to have_been_requested
  expect(@sns.sent).to eq(1)
end

Then /^the user should receive an email notification$/ do
  expect(Mail::TestMailer.deliveries.length).to eq(1)
  expect(@email.sent).to eq(1)
end

Then /^the user should not receive an SMS notification$/ do
  expect(@request).to have_been_requested
  expect(@sms.sent).to eq(0)
end

Then /^the user should not receive an SNS notification$/ do
  expect(@request).to have_been_requested
  expect(@sns.sent).to eq(0)
end

Then /^the user should not receive an email notification$/ do
  expect(Mail::TestMailer.deliveries).to be_empty
  expect(@email.sent).to eq(0)
end
