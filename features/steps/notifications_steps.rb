require 'flapjack/gateways/aws_sns'
require 'flapjack/gateways/email'
require 'flapjack/gateways/sms_messagenet'

def find_or_create_contact(contact_data)
  contact = Flapjack::Data::Contact.intersect(:name => contact_data[:name]).all.first
  if contact.nil?
    contact = Flapjack::Data::Contact.new(:name => contact_data[:name])
    expect(contact.save).to be true
  end

  contact
end

def find_or_create_check(check_data)
  check = Flapjack::Data::Check.intersect(:name => check_data[:name]).all.first

  if check.nil?
    check = Flapjack::Data::Check.new(:name => check_data[:name])
    expect(check.save).to be true

    entity_name, check_name = check_data[:name].split(':', 2)

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

Given /^the following contacts exist:$/ do |contacts|
  contacts.hashes.each do |contact_data|
    contact = Flapjack::Data::Contact.find_by_id(contact_data['id'])
    expect(contact).to be nil
    contact = Flapjack::Data::Contact.new(
      :id       => contact_data['id'],
      :name     => contact_data['name'],
      :timezone => contact_data['timezone']
    )
    expect(contact.save).to be true
  end
end

Given /^the following checks exist:$/ do |checks|
  checks.hashes.each do |check_data|
    check = Flapjack::Data::Check.find_by_id(check_data['id'])
    expect(check).to be nil

    check = Flapjack::Data::Check.new(
      :id   => check_data['id'],
      :name => check_data['name']
    )
    expect(check.save).to be true

    unless check_data['tags'].nil? || check_data['tags'].strip.empty?
      check_data['tags'].split(',').map(&:strip).each do |tag_name|
        tag = Flapjack::Data::Tag.intersect(:name => tag_name).all.first
        if tag.nil?
          tag = Flapjack::Data::Tag.new(:name => tag_name)
          tag.save
        end
        check.tags << tag
      end
    end
  end
end

Given /^the following media exist:$/ do |media|
  media.hashes.each do |medium_data|
    contact = Flapjack::Data::Contact.find_by_id(medium_data['contact_id'])
    expect(contact).not_to be nil

    medium = Flapjack::Data::Medium.find_by_id(medium_data['id'])
    expect(medium).to be nil
    medium = Flapjack::Data::Medium.new(
      :id               => medium_data['id'],
      :type             => medium_data['type'],
      :address          => medium_data['address'],
      :interval         => medium_data['interval'].to_i * 60,
      :rollup_threshold => medium_data['rollup_threshold'].to_i
    )
    expect(medium.save).to be true
    contact.media << medium
  end
end

Given /^the following rules exist:$/ do |rules|
  rules.hashes.each do |rule_data|
    contact = Flapjack::Data::Contact.find_by_id(rule_data['contact_id'])
    expect(contact).not_to be nil

    rule = Flapjack::Data::Rule.find_by_id(rule_data['id'])
    expect(rule).to be nil

    rule = Flapjack::Data::Rule.new(
      :id          => rule_data['id'],
      :is_specific => false
    )
    expect(rule.save).to be true

    unless rule_data['tags'].nil? || rule_data['tags'].strip.empty?
      rule_data['tags'].split(',').map(&:strip).each do |tag_name|
        tag = Flapjack::Data::Tag.intersect(:name => tag_name).all.first
        if tag.nil?
          tag = Flapjack::Data::Tag.new(:name => tag_name)
          expect(tag.save).to be true
        end
        rule.tags << tag
      end
      rule.is_specific = true
      expect(rule.save).to be true
    end

    contact.rules << rule
  end
end

Given /^the following routes exist:$/ do |routes|
  routes.hashes.each do |route_data|
    rule = Flapjack::Data::Rule.find_by_id(route_data['rule_id'])
    expect(rule).not_to be nil

    contact = rule.contact
    expect(rule.contact).not_to be nil

    time_zone = contact.time_zone
    expect(time_zone).to be_an ActiveSupport::TimeZone

    route = Flapjack::Data::Route.find_by_id(route_data['id'])
    expect(route).to be nil

    route = Flapjack::Data::Route.new(
      :id    => route_data['id'],
      :state => (route_data['state'].nil? || route_data['state'].empty?) ? nil : route_data['state'],
      :drop  => !(route_data['drop'].nil? || route_data['drop'].strip.empty?)
    )
    unless route_data['time_restrictions'].nil? || route_data['time_restrictions'].strip.empty?
      route.time_restrictions = route_data['time_restrictions'].split(',').map(&:strip).inject([]) do |memo, tr|
        case tr
        when '8-18 weekdays'
          weekdays_8_18 = IceCube::Schedule.new(time_zone.local(2013,2,1,8,0,0), :duration => 60 * 60 * 10)
          weekdays_8_18.add_recurrence_rule(IceCube::Rule.weekly.day(:monday, :tuesday, :wednesday, :thursday, :friday))
          memo << icecube_schedule_to_time_restriction(weekdays_8_18, time_zone)
        end
        memo
      end
    end
    expect(route.save).to be true

    unless route_data['media_ids'].nil? || route_data['media_ids'].strip.empty?
      media_ids = route_data['media_ids'].split(',').map(&:strip)
      media = Flapjack::Data::Medium.find_by_ids(*media_ids)
      expect(media.map(&:id)).to match_array(media_ids)
      route.media.add(*media) unless media.empty?
    end
    rule.routes << route
  end
end

Given /^(?:a|the) user wants to receive SMS notifications for check '(.+)'$/ do |check_name|
  contact = find_or_create_contact(:name => 'John Smith')

  sms = Flapjack::Data::Medium.new(:type => 'sms',
    :address => '+61888888888', :interval => 600)
  expect(sms.save).to be true
  contact.media << sms

  check = find_or_create_check(:name => check_name)

  rule = Flapjack::Data::Rule.new
  expect(rule.save).to be true

  check_name.split(':', 2).each do |tag_name|
    tag = Flapjack::Data::Tag.intersect(:name => tag_name).all.first
    if tag.nil?
      tag = Flapjack::Data::Tag.new(:name => tag_name)
      expect(tag.save).to be true
    end
    rule.tags << tag
    check.tags << tag
  end

  rule.is_specific = true
  expect(rule.save).to be true

  route = Flapjack::Data::Route.new(:state => 'critical')
  expect(route.save).to be true

  route.media << sms
  rule.routes << route

  contact.rules << rule
end

Given /^(?:a|the) user wants to receive email notifications for check '(.+)'$/ do |check_name|
  contact = find_or_create_contact(:name => 'Jane Smith')

  email = Flapjack::Data::Medium.new(:type => 'email',
    :address => 'janes@example.dom', :interval => 600)
  expect(email.save).to be true
  contact.media << email

  check = find_or_create_check(:name => check_name)

  rule = Flapjack::Data::Rule.new
  expect(rule.save).to be true

  check_name.split(':', 2).each do |tag_name|
    tag = Flapjack::Data::Tag.intersect(:name => tag_name).all.first
    if tag.nil?
      tag = Flapjack::Data::Tag.new(:name => tag_name)
      expect(tag.save).to be true
    end
    rule.tags << tag
    check.tags << tag
  end

  rule.is_specific = true
  rule.save

  route = Flapjack::Data::Route.new(:state => 'critical')
  expect(route.save).to be true

  route.media << email
  rule.routes << route
  contact.rules << rule
end

Given /^(?:a|the) user wants to receive SNS notifications for check '(.+)'$/ do |check_name|
  contact = find_or_create_contact(:name => 'James Smithson')

  sns = Flapjack::Data::Medium.new(:type => 'sns',
    :address => 'arn:aws:sns:us-east-1:698519295917:My-Topic', :interval => 600)
  expect(sns.save).to be true
  contact.media << sns

  check = find_or_create_check(:name => check_name)

  rule = Flapjack::Data::Rule.new
  expect(rule.save).to be true

  check_name.split(':', 2).each do |tag_name|
    tag = Flapjack::Data::Tag.intersect(:name => tag_name).all.first
    if tag.nil?
      tag = Flapjack::Data::Tag.new(:name => tag_name)
      expect(tag.save).to be true
    end
    rule.tags << tag
    check.tags << tag
  end

  rule.is_specific = true
  rule.save

  route = Flapjack::Data::Route.new(:state => 'critical')
  expect(route.save).to be true

  route.media << sns
  rule.routes << route
  contact.rules << rule
end

# TODO create the notification object in redis, flag the relevant operation as
# only needing that part running, split up the before block that covers these
When /^an event notification is generated for check '(.+)'$/ do |check_name|
  timestamp = Time.now.to_i

  event = Flapjack::Data::Event.new('type'    => 'service',
                                    'state'   => 'critical',
                                    'summary' => '100% packet loss',
                                    'entity'  => check_name.split(':', 2).first,
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

  # notification.tags.add(*check.tags.all) unless check.tags.empty?

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

  medium = Flapjack::Data::Medium.intersect(:type => media_type.downcase).all.first
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
