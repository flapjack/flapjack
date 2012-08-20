@events
Feature: events
  So people can be notified when things break and recover
  flapjack-executive must process events correctly

  Scenario: Check ok to ok
    Given check x is in an ok state
    When  an ok event is received for check x
    Then  a notification should not be generated for check x
    And   show me the output

  Scenario: Check ok to failed
    Given check x is in an ok state
    And   a failure event is received for check x
    Then  a notification should not be generated for check x

  @time
  Scenario: Check failed to failed after 10 seconds
    Given check x is in an ok state
    When  a failure event is received for check x
    And   10 seconds passes
    And   a failure event is received for check x
    Then  a notification should not be generated for check x

  @time
  Scenario: Check ok to failed for 1 minute
    Given check x is in an ok state
    When  a failure event is received for check x
    And   1 minute passes
    And   a failure event is received for check x
    Then  a notification should be generated for check x
    
  @time
  Scenario: Check failed and alerted to failed for 1 minute
    Given check x is in an ok state
    When  a failure event is received for check x
    And   1 minute passes
    And   a failure event is received for check x
    Then  a notification should be generated for check x
    When  1 minute passes
    And   a failure event is received for check x
    Then  a notification should not be generated for check x

  @time
  Scenario: Check failed and alerted to failed for 6 minutes
    Given check x is in an ok state
    When  a failure event is received for check x
    And   1 minute passes
    And   a failure event is received for check x
    Then  a notification should be generated for check x
    When  6 minutes passes
    And   a failure event is received for check x
    Then  a notification should be generated for check x

  @time
  Scenario: Check ok to failed for 1 minute when in scheduled maintenance
    Given check x is in an ok state
    And   check x is in scheduled maintenance
    When  a failure event is received for check x
    And   1 minute passes
    And   a failure event is received for check x
    Then  a notification should not be generated for check x

  @time
  Scenario: Check ok to failed for 1 minute when in unscheduled maintenance
    Given check x is in an ok state
    And   check x is in unscheduled maintenance
    When  a failure event is received for check x
    And   1 minute passes
    And   a failure event is received for check x
    Then  a notification should not be generated for check x

  @time
  Scenario: Check ok to failed for 1 minute, acknowledged, and failed for 6 minutes
    Given check x is in an ok state
    When  a failure event is received for check x
    And   1 minute passes
    And   a failure event is received for check x
    Then  a notification should be generated for check x
    When  an acknowledgement is received for check x
    And   6 minute passes
    And   a failure event is received for check x
    Then  a notification should not be generated for check x
  
  Scenario: Check failed to ok
    Given check x is in a failure state
    When  an ok event is received for check x
    Then  a notification should be generated for check x

  @time
  Scenario: Check failed to ok when acknowledged
    Given check x is in a failure state
    When  an acknowledgement event is received for check x
    Then  a notification should be generated for check x
    When  1 minute passes
    And   an ok event is received for check x
    Then  a notification should be generated for check x

  @time
  Scenario: Check failed to ok when acknowledged, and fails after 6 minutes
    Given check x is in a failure state
    When  an acknowledgement event is received for check x
    Then  a notification should be generated for check x
    When  1 minute passes
    And   an ok event is received for check x
    Then  a notification should be generated for check x
    When  6 minutes passes
    And   a failure event is received for check x
    Then  a notification should not be generated for check x
    When  6 minutes passes
    And   a failure event is received for check x
    Then  a notification should be generated for check x

  Scenario: Acknowledgement when ok
    Given check x is in an ok state
    When  an acknowledgement event is received for check x
    Then  a notification should not be generated for check x

  Scenario: Acknowledgement when failed
    Given check x is in a failure state
    When  an acknowledgement event is received for check x
    Then  a notification should be generated for check x
