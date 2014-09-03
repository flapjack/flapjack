@notifications @processor @notifier
Feature: notifications
  So people can be notified when things break and recover
  flapjack-notifier must send notifications correctly

  # TODO test across multiple contacts

  Scenario: Queue an SMS notification
    Given the user wants to receive SMS notifications for entity 'example.com'
    When an event notification is generated for entity 'example.com'
    Then an SMS notification for entity 'example.com' should be queued
    And an email notification for entity 'example.com' should not be queued

  Scenario: Queue an SNS notification
    Given the user wants to receive SNS notifications for entity 'example.com'
    When an event notification is generated for entity 'example.com'
    Then an SNS notification for entity 'example.com' should be queued
    And an email notification for entity 'example.com' should not be queued

  Scenario: Queue an email notification
    Given the user wants to receive email notifications for entity 'example.com'
    When an event notification is generated for entity 'example.com'
    Then an email notification for entity 'example.com' should be queued
    And an SMS notification for entity 'example.com' should not be queued

  Scenario: Queue SMS and email notifications
    Given a user wants to receive SMS notifications for entity 'example.com'
    And a user wants to receive email notifications for entity 'example2.com'
    When an event notification is generated for entity 'example.com'
    And an event notification is generated for entity 'example2.com'
    Then an SMS notification for entity 'example.com' should be queued
    And an SMS notification for entity 'example2.com' should not be queued
    Then an email notification for entity 'example.com' should not be queued
    And an email notification for entity 'example2.com' should be queued

  Scenario: Send a queued SMS notification
    Given a user wants to receive SMS notifications for entity 'example.com'
    And an SMS notification has been queued for entity 'example.com'
    When the SMS notification handler runs successfully
    Then the user should receive an SMS notification

  Scenario: Send a queued SNS notification
    Given a user wants to receive SNS notifications for entity 'example.com'
    And an SNS notification has been queued for entity 'example.com'
    When the SNS notification handler runs successfully
    Then the user should receive an SNS notification

  Scenario: Handle a failure to send a queued SMS notification
    Given a user wants to receive SMS notifications for entity 'example.com'
    And an SMS notification has been queued for entity 'example.com'
    When the SMS notification handler fails to send an SMS
    Then the user should not receive an SMS notification

  Scenario: Handle a failure to send a queued SNS notification
    Given a user wants to receive SNS notifications for entity 'example.com'
    And an SNS notification has been queued for entity 'example.com'
    When the SNS notification handler fails to send an SMS
    Then the user should not receive an SNS notification

  Scenario: Send a queued email notification
    Given a user wants to receive email notifications for entity 'example.com'
    And an email notification has been queued for entity 'example.com'
    When the email notification handler runs successfully
    Then the user should receive an email notification

  Scenario: Handle a failure to send a queued email notification
    Given a user wants to receive email notifications for entity 'example.com'
    And an email notification has been queued for entity 'example.com'
    When the email notification handler fails to send an email
    Then the user should not receive an email notification
