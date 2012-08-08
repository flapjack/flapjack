def send_sms(notification)
  begin
    Flapjack::Notification::Sms.perform(notification)
    true
  rescue Exception => e
    # puts e.message
    # puts e.backtrace.join("\n")
    false
  end
end

def send_email(notification)
  begin
    Flapjack::Notification::Email.perform(notification)
    true
  rescue Exception => e
    # puts e.message    # puts e.backtrace.join("\n")
    false
  end
end

Given /^a user SMS notification has been generated$/ do
  @sms_notification = {'notification_type'  => 'problem',
                       'contact_first_name' => 'John',
                       'contact_last_name'  => 'Smith',
                       'state'              => 'CRITICAL',
                       'summary'            => 'Socket timeout after 10 seconds',
                       'time'               => Time.now.to_i,
                       'event_id'           => 'b99999.darwin03-viprion-blade8',
                       'address'            => '+61412345678',
                       'id'                 => 1}
end

Given /^a user email notification has been generated$/ do
  @email_notification = {'notification_type'  => 'problem',
                        'contact_first_name' => 'John',
                        'contact_last_name'  => 'Smith',
                        'state'              => 'CRITICAL',
                        'summary'            => 'Socket timeout after 10 seconds',
                        'time'               => Time.now.to_i,
                        'event_id'           => 'b99999.darwin03-viprion-blade8',
                        'address'            => 'johns@example.dom',
                        'id'                 => 2}
end

# TODO may need to get more complex, depending which SMS provider is used
When /^the SMS notification handler runs successfully$/ do
  # returns success by default - currently matches all addresses, maybe load from config?
  stub_request(:get, /.*/)

  @sms_sent = send_sms(@sms_notification)
end

When /^the SMS notification handler fails to send an SMS$/ do
  stub_request(:any, /.*/).to_return(:status => [500, "Internal Server Error"])

  @sms_sent = send_sms(@sms_notification)
end

When /^the email notification handler runs successfully$/ do
  send_email(@email_notification)
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
