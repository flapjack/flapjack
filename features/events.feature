@events
Feature: events
  So people can be notified when things break and recover
  flapjack-executive must process events correctly

  # TODO make entity and check implicit, so the test reads more cleanly
  Background:
    Given an entity 'def' exists

  Scenario: Check ok to ok
    Given the check is check 'abc' on entity 'def'
    Given the check is in an ok state
    When  an ok event is received
    Then  a notification should not be generated

  Scenario: Check ok to failed
    Given the check is check 'abc' on entity 'def'
    Given the check is in an ok state
    When  a failure event is received
    Then  a notification should not be generated

  @time
  Scenario: Check failed to failed after 10 seconds
    Given the check is check 'abc' on entity 'def'
    Given the check is in an ok state
    When  a failure event is received
    And   10 seconds passes
    And   a failure event is received
    Then  a notification should not be generated

  @time
  Scenario: Check ok to failed for 1 minute
    Given the check is check 'abc' on entity 'def'
    Given the check is in an ok state
    When  a failure event is received
    And   1 minute passes
    And   a failure event is received
    Then  a notification should be generated

  @time
  Scenario: Check failed and alerted to failed for 1 minute
    Given the check is check 'abc' on entity 'def'
    Given the check is in an ok state
    When  a failure event is received
    And   1 minute passes
    And   a failure event is received
    Then  a notification should be generated
    When  1 minute passes
    And   a failure event is received
    Then  a notification should not be generated

  @time
  Scenario: Check failed and alerted to failed for 6 minutes
    Given the check is check 'abc' on entity 'def'
    Given the check is in an ok state
    When  a failure event is received
    And   1 minute passes
    And   a failure event is received
    Then  a notification should be generated
    When  6 minutes passes
    And   a failure event is received
    Then  a notification should be generated

  @time
  Scenario: Check ok to failed for 1 minute when in scheduled maintenance
    Given the check is check 'abc' on entity 'def'
    Given the check is in an ok state
    And   the check is in scheduled maintenance
    When  a failure event is received
    And   1 minute passes
    And   a failure event is received
    Then  a notification should not be generated

  @time
  Scenario: Check ok to failed for 1 minute when in unscheduled maintenance
    Given the check is check 'abc' on entity 'def'
    Given the check is in an ok state
    And   the check is in unscheduled maintenance
    When  a failure event is received
    And   1 minute passes
    And   a failure event is received
    Then  a notification should not be generated

  @time
  Scenario: Check ok to failed for 1 minute, acknowledged, and failed for 6 minutes
    Given the check is check 'abc' on entity 'def'
    Given the check is in an ok state
    When  a failure event is received
    And   1 minute passes
    And   a failure event is received
    Then  a notification should be generated
    When  an acknowledgement event is received
    And   6 minute passes
    And   a failure event is received
    Then  a notification should not be generated

  Scenario: Check failed to ok
    Given the check is check 'abc' on entity 'def'
    Given the check is in a failure state
    And   5 minutes passes
    And   a failure event is received
    Then  a notification should be generated
    When  5 minutes passes
    And   an ok event is received
    Then  a notification should be generated

  @time
  Scenario: Check failed to ok when acknowledged
    Given the check is check 'abc' on entity 'def'
    Given the check is in a failure state
    When  an acknowledgement event is received
    Then  a notification should be generated
    When  1 minute passes
    And   an ok event is received
    Then  a notification should be generated

  @time
  Scenario: Check failed to ok when acknowledged, and fails after 6 minutes
    Given the check is check 'abc' on entity 'def'
    Given the check is in a failure state
    When  an acknowledgement event is received
    Then  a notification should be generated
    When  1 minute passes
    And   an ok event is received
    Then  a notification should be generated
    When  6 minutes passes
    And   a failure event is received
    Then  a notification should not be generated
    When  6 minutes passes
    And   a failure event is received
    Then  a notification should be generated

  @time
  Scenario: Osciliating state, period of two minutes
    Given the check is check 'abc' on entity 'def'
    Given the check is in an ok state
    When  a failure event is received
    Then  a notification should not be generated
    When  50 seconds passes
    And   a failure event is received
    Then  a notification should be generated
    When  10 seconds passes
    And   an ok event is received
    Then  a notification should be generated
    When  50 seconds passes
    And   an ok event is received
    Then  a notification should not be generated
    When  10 seconds passes
    And   a failure event is received
    Then  a notification should not be generated
    When  50 seconds passes
    And   a failure event is received
    #And   show me the notifications
    Then  a notification should be generated
    When  10 seconds passes
    And   an ok event is received
    Then  a notification should be generated

  Scenario: Acknowledgement when ok
    Given the check is check 'abc' on entity 'def'
    Given the check is in an ok state
    When  an acknowledgement event is received
    Then  a notification should not be generated

  Scenario: Acknowledgement when failed
    Given the check is check 'abc' on entity 'def'
    Given the check is in a failure state
    When  an acknowledgement event is received
    Then  a notification should be generated

  Scenario: Brief failure then OK
    Given the check is check 'abc' on entity 'def'
    Given the check is in an ok state
    When  a failure event is received
    And   10 seconds passes
    And   an ok event is received
    Then  a notification should not be generated

  Scenario: Flapper (down for one minute, up for one minute, repeat)
    Given the check is check 'abc' on entity 'def'
    Given the check is in an ok state
    When  a failure event is received
    Then  a notification should not be generated
    When  10 seconds passes
    And   a failure event is received
    Then  a notification should not be generated
    When  10 seconds passes
    And   a failure event is received
    Then  a notification should not be generated
    When  10 seconds passes
    # 30 seconds
    And   a failure event is received
    Then  a notification should be generated
    When  10 seconds passes
    And   a failure event is received
    Then  a notification should not be generated
    When  10 seconds passes
    And   a failure event is received
    Then  a notification should not be generated
    When  10 seconds passes
    # 60 seconds
    And   an ok event is received
    Then  a notification should be generated
    When  10 seconds passes
    And   an ok event is received
    Then  a notification should not be generated
    When  10 seconds passes
    And   an ok event is received
    Then  a notification should not be generated
    When  10 seconds passes
    And   an ok event is received
    Then  a notification should not be generated
    When  10 seconds passes
    And   an ok event is received
    Then  a notification should not be generated
    When  10 seconds passes
    And   an ok event is received
    Then  a notification should not be generated
    When  10 seconds passes
    # 120 seconds
    And   a failure event is received
    Then  a notification should not be generated
    When  10 seconds passes
    And   a failure event is received
    Then  a notification should not be generated
    When  10 seconds passes
    And   a failure event is received
    Then  a notification should not be generated
    When  10 seconds passes
    # 150 seconds
    And   a failure event is received
    Then  a notification should be generated
    When  10 seconds passes
    And   a failure event is received
    Then  a notification should not be generated
    When  10 seconds passes
    And   a failure event is received
    Then  a notification should not be generated
    When  10 seconds passes
    # 180 seconds
    And   an ok event is received
    Then  a notification should be generated
