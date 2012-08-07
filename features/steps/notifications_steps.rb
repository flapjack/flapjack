# TODO may want to refactor steps to different functional groups

# NB: This is several steps away from Cucumber best practice, and won't work yet --
# I'm just working out a rough flow.

Given /^a user SMS notification has been generated$/ do
  pending
  @sms_notification = {}
end

Given /^a user email notification has been generated$/ do
  pending
  @email_notification = {}
end

# Could use https://github.com/bblimke/webmock if we want to get fancy -- but
# this should do for now
When /^the SMS notification handler runs successfully$/ do
  pending
  request = mock('http_request')
  Net::HTTP::Get.should_receive(:new).and_return(request)
  http = mock('http')
  http.should_receive(:request).with(request).and_return(Net::HTTPSuccess.new)
  Net::HTTP.should_receive(:start).and_yield(http)

  Flapjack::Notification::SMS.perform(@sms_notification)
end

When /^the SMS notification handler fails to send an SMS$/ do
  pending
  request = mock('http_request')
  Net::HTTP::Get.should_receive(:new).and_return(request)
  http = mock('http')
  http.should_receive(:request).with(request).and_return(Net::HTTPError.new)
  Net::HTTP.should_receive(:start).and_yield(http)

  Flapjack::Notification::SMS.perform(@sms_notification)
end

When /^the email notification handler runs successfully$/ do
  pending
  # Flapjack::Notification::Email.perform(@email_notification)
end

When /^the email notification handler fails to send an email$/ do
  pending
end

Then /^the user should receive an SMS notification$/ do
  pending
end

Then /^the user should receive an email notification$/ do
  pending
end

Then /^the user should not receive an SMS notification$/ do
  pending
end

Then /^the user should not receive an email notification$/ do
  pending # express the regexp above with the code you wish you had
end

