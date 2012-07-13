@events
Feature: events
  So people can be notified when things break and recover
  Flapjack-notifier must process events correctly

  Scenario: Service ok to ok
    Given service x is in an ok state
    When  an ok event is received for service x
    Then  a notification should not be generated for service x
    And   show me the output

  @time
  Scenario: Service ok to failed
    Given service x is in an ok state
    And   a failure event is received for service x
    Then  a notification should not be generated for service x

  @time
  Scenario: Service failed to failed after 10 seconds
    Given service x is in an ok state
    When  a failure event is received for service x
    And   10 seconds passes
    And   a failure event is received for service x
    Then  a notification should not be generated for service x

  Scenario: Service ok to failed for 1 minute
    Given service x is in an ok state
    When  a failure event is received for service x
    And   1 minute passes
    And   a failure event is received for service x
    Then  a notification should be generated for service x

  Scenario: Service failed and alerted to failed for 1 minute
    Given service x is in an ok state
    When  a failure event is received for service x
    And   1 minute passes
    And   a failure event is received for service x
    Then  a notification should be generated for service x
    When  1 minute passes
    And   a failure event is received for service x
    Then  a notification should not be generated for service x

  Scenario: Service failed and alerted to failed for 6 minutes
    Given service x is in an ok state
    When  a failure event is received for service x
    And   1 minute passes
    And   a failure event is received for service x
    Then  a notification should be generated for service x
    When  6 minutes passes
    And   a failure event is received for service x
    Then  a notification should be generated for service x

  Scenario: Service ok to failed for 1 minute when in scheduled maintenance
    Given service x is in an ok state
    And   service x is in scheduled maintenance
    When  a failure event is received for service x
    And   1 minute passes
    And   a failure event is received for service x
    Then  a notification should not be generated for service x

  Scenario: Service ok to failed for 1 minute when in unscheduled maintenance
    Given service x is in an ok state
    And   service x is in unscheduled maintenance
    When  a failure event is received for service x
    And   1 minute passes
    And   a failure event is received for service x
    Then  a notification should not be generated for service x

  Scenario: Service ok to failed for 1 minute, acknowledged, and failed for 6 minutes
    Given service x is in an ok state
    When  a failure event is received for service x
    And   1 minute passes
    And   a failure event is received for service x
    Then  a notification should be generated for service x
    When  an acknowledgement is received for service x
    And   6 minute passes
    And   a failure event is received for service x
    Then  a notification should not be generated for service x

  Scenario: Service failed to ok
    Given service x is in a failure state
    When  an ok event is received for service x
    Then  a notification should be generated for service x

  Scenario: Service failed to ok when acknowledged
    Given service x is in a failure state
    When  an acknowledgement event is received for service x
    Then  a notification should be generated for service x
    When  1 minute passes
    And   an ok event is received for service x
    Then  a notification should be generated for service x

  Scenario: Service failed to ok when acknowledged, and fails after 6 minutes
    Given service x is in a failure state
    When  an acknowledgement event is received for service x
    Then  a notification should be generated for service x
    When  1 minute passes
    And   an ok event is received for service x
    Then  a notification should be generated for service x
    When  6 minutes passes
    And   a failure event is received for service x
    Then  a notification should not be generated for service x
    When  6 minutes passes
    And   a failure event is received for service x
    Then  a notification should be generated for service x

  Scenario: Acknowledgement when ok
    Given service x is in an ok state
    When  an acknowledgement event is received for service x
    Then  a notification should not be generated for service x

  Scenario: Acknowledgement when failed
    Given service x is in a failure state
    When  an acknowledgement event is received for service x
    Then  a notification should be generated for service x

