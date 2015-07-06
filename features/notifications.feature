@notifications @processor @notifier
Feature: notifications
  So people can be notified when things break and recover
  flapjack-notifier must send notifications correctly

  # TODO test across multiple contacts

  Scenario: Queue an SMS alert
    Given the user wants to receive SMS alerts for check 'example.com:PING'
    When an event notification is generated for check 'example.com:PING'
    Then an SMS alert for check 'example.com:PING' should be queued
    And an email alert for check 'example.com:PING' should not be queued

  Scenario: Queue a Nexmo alert
    Given the user wants to receive Nexmo alerts for check 'example.com:PING'
    When an event notification is generated for check 'example.com:PING'
    Then a Nexmo alert for check 'example.com:PING' should be queued
    And an email alert for check 'example.com:PING' should not be queued
    And an SMS alert for check 'example.com:PING' should not be queued

  Scenario: Queue an SNS alert
    Given the user wants to receive SNS alerts for check 'example.com:PING'
    When an event notification is generated for check 'example.com:PING'
    Then an SNS alert for check 'example.com:PING' should be queued
    And an email alert for check 'example.com:PING' should not be queued

  Scenario: Queue an email alert
    Given the user wants to receive email alerts for check 'example.com:PING'
    When an event notification is generated for check 'example.com:PING'
    Then an email alert for check 'example.com:PING' should be queued
    And an SMS alert for check 'example.com:PING' should not be queued

  Scenario: Queue SMS and email alerts
    Given a user wants to receive SMS alerts for check 'example.com:PING'
    And a user wants to receive email alerts for check 'example2.com:SSH'
    When an event notification is generated for check 'example.com:PING'
    And an event notification is generated for check 'example2.com:SSH'
    Then an SMS alert for check 'example.com:PING' should be queued
    And an SMS alert for check 'example2.com:SSH' should not be queued
    Then an email alert for check 'example.com:PING' should not be queued
    And an email alert for check 'example2.com:SSH' should be queued

  Scenario: Send a queued SMS alert
    Given a user wants to receive SMS alerts for check 'example.com:PING'
    And an SMS alert has been queued for check 'example.com:PING'
    When the SMS alert handler runs successfully
    Then the user should receive an SMS alert

  Scenario: Send a queued Nexmo alert
    Given a user wants to receive Nexmo alerts for check 'example.com:PING'
    And a Nexmo alert has been queued for check 'example.com:PING'
    When the Nexmo alert handler runs successfully
    Then the user should receive a Nexmo alert

  Scenario: Send a queued SNS alert
    Given a user wants to receive SNS alerts for check 'example.com:PING'
    And an SNS alert has been queued for check 'example.com:PING'
    When the SNS alert handler runs successfully
    Then the user should receive an SNS alert

  Scenario: Handle a failure to send a queued SMS alert
    Given a user wants to receive SMS alerts for check 'example.com:PING'
    And an SMS alert has been queued for check 'example.com:PING'
    When the SMS alert handler fails to send an SMS
    Then the user should not receive an SMS alert

  Scenario: Handle a failure to send a queued SNS alert
    Given a user wants to receive SNS alerts for check 'example.com:PING'
    And an SNS alert has been queued for check 'example.com:PING'
    When the SNS alert handler fails to send an SMS
    Then the user should not receive an SNS alert

  Scenario: Send a queued email alert
    Given a user wants to receive email alerts for check 'example.com:PING'
    And an email alert has been queued for check 'example.com:PING'
    When the email alert handler runs successfully
    Then the user should receive an email alert

  Scenario: Handle a failure to send a queued email alert
    Given a user wants to receive email alerts for check 'example.com:PING'
    And an email alert has been queued for check 'example.com:PING'
    When the email alert handler fails to send an email
    Then the user should not receive an email alert
