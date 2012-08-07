@notifications
Feature: notifications
  So people can be notified when things break and recover
  flapjack-notifier must send notifications correctly

# TODO specific notification to host -- check that user gets
# message for one host but not for another?

Scenario: Send an SMS notification
  Given a user SMS notification has been generated
  When the SMS notification handler runs successfully
  Then the user should receive an SMS notification

Scenario: Handle a failure to send an SMS notification
  Given a user SMS notification has been generated
  When the SMS notification handler fails to send an SMS
  Then the user should not receive an SMS notification

Scenario: Send an email notification
  Given a user email notification has been generated
  When the email notification handler runs successfully
  Then the user should receive an email notification

Scenario: Handle a failure to send an email notification
  Given a user email notification has been generated
  When the email notification handler fails to send an email
  Then the user should not receive an email notification