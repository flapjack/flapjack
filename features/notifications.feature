@notifications @processor @notifier
Feature: notifications
  So people can be notified when things break and recover
  flapjack-notifier must send notifications correctly

  # TODO test across multiple contacts

  Scenario: Queue an SMS notification
    Given the user wants to receive SMS notifications for check 'example.com:PING'
    When an event notification is generated for check 'example.com:PING'
    Then an SMS notification for check 'example.com:PING' should be queued
    And an email notification for check 'example.com:PING' should not be queued

  Scenario: Queue an SNS notification
    Given the user wants to receive SNS notifications for check 'example.com:PING'
    When an event notification is generated for check 'example.com:PING'
    Then an SNS notification for check 'example.com:PING' should be queued
    And an email notification for check 'example.com:PING' should not be queued

  Scenario: Queue an email notification
    Given the user wants to receive email notifications for check 'example.com:PING'
    When an event notification is generated for check 'example.com:PING'
    Then an email notification for check 'example.com:PING' should be queued
    And an SMS notification for check 'example.com:PING' should not be queued

  Scenario: Queue SMS and email notifications
    Given a user wants to receive SMS notifications for check 'example.com:PING'
    And a user wants to receive email notifications for check 'example2.com:SSH'
    When an event notification is generated for check 'example.com:PING'
    And an event notification is generated for check 'example2.com:SSH'
    Then an SMS notification for check 'example.com:PING' should be queued
    And an SMS notification for check 'example2.com:SSH' should not be queued
    Then an email notification for check 'example.com:PING' should not be queued
    And an email notification for check 'example2.com:SSH' should be queued

  Scenario: Send a queued SMS notification
    Given a user wants to receive SMS notifications for check 'example.com:PING'
    And an SMS notification has been queued for check 'example.com:PING'
    When the SMS notification handler runs successfully
    Then the user should receive an SMS notification

  Scenario: Send a queued SNS notification
    Given a user wants to receive SNS notifications for check 'example.com:PING'
    And an SNS notification has been queued for check 'example.com:PING'
    When the SNS notification handler runs successfully
    Then the user should receive an SNS notification

  Scenario: Handle a failure to send a queued SMS notification
    Given a user wants to receive SMS notifications for check 'example.com:PING'
    And an SMS notification has been queued for check 'example.com:PING'
    When the SMS notification handler fails to send an SMS
    Then the user should not receive an SMS notification

  Scenario: Handle a failure to send a queued SNS notification
    Given a user wants to receive SNS notifications for check 'example.com:PING'
    And an SNS notification has been queued for check 'example.com:PING'
    When the SNS notification handler fails to send an SMS
    Then the user should not receive an SNS notification

  Scenario: Send a queued email notification
    Given a user wants to receive email notifications for check 'example.com:PING'
    And an email notification has been queued for check 'example.com:PING'
    When the email notification handler runs successfully
    Then the user should receive an email notification

  Scenario: Handle a failure to send a queued email notification
    Given a user wants to receive email notifications for check 'example.com:PING'
    And an email notification has been queued for check 'example.com:PING'
    When the email notification handler fails to send an email
    Then the user should not receive an email notification
