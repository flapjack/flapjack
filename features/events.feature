@events
Feature: events
  So people can be notified when things break and recover
  flapjack-executive must process events correctly

  # TODO make entity and check implicit, so the test reads more cleanly
  Background:
    Given an entity 'def' exists

  Scenario: Check ok to ok
    Given check 'abc' for entity 'def' is in an ok state
    When  an ok event is received for check 'abc' on entity 'def'
    Then  a notification should not be generated for check 'abc' on entity 'def'

  Scenario: Check ok to failed
    Given check 'abc' for entity 'def' is in an ok state
    When  a failure event is received for check 'abc' on entity 'def'
    Then  a notification should not be generated for check 'abc' on entity 'def'

  @time
  Scenario: Check failed to failed after 10 seconds
    Given check 'abc' for entity 'def' is in an ok state
    When  a failure event is received for check 'abc' on entity 'def'
    And   10 seconds passes
    And   a failure event is received for check 'abc' on entity 'def'
    Then  a notification should not be generated for check 'abc' on entity 'def'

  @time
  Scenario: Check ok to failed for 1 minute
    Given check 'abc' for entity 'def' is in an ok state
    When  a failure event is received for check 'abc' on entity 'def'
    And   1 minute passes
    And   a failure event is received for check 'abc' on entity 'def'
    Then  a notification should be generated for check 'abc' on entity 'def'

  @time
  Scenario: Check failed and alerted to failed for 1 minute
    Given check 'abc' for entity 'def' is in an ok state
    When  a failure event is received for check 'abc' on entity 'def'
    And   1 minute passes
    And   a failure event is received for check 'abc' on entity 'def'
    Then  a notification should be generated for check 'abc' on entity 'def'
    When  1 minute passes
    And   a failure event is received for check 'abc' on entity 'def'
    Then  a notification should not be generated for check 'abc' on entity 'def'

  @time
  Scenario: Check failed and alerted to failed for 6 minutes
    Given check 'abc' for entity 'def' is in an ok state
    When  a failure event is received for check 'abc' on entity 'def'
    And   1 minute passes
    And   a failure event is received for check 'abc' on entity 'def'
    Then  a notification should be generated for check 'abc' on entity 'def'
    When  6 minutes passes
    And   a failure event is received for check 'abc' on entity 'def'
    Then  a notification should be generated for check 'abc' on entity 'def'

  @time
  Scenario: Check ok to failed for 1 minute when in scheduled maintenance
    Given check 'abc' for entity 'def' is in an ok state
    And   check 'abc' for entity 'def' is in scheduled maintenance
    When  a failure event is received for check 'abc' on entity 'def'
    And   1 minute passes
    And   a failure event is received for check 'abc' on entity 'def'
    Then  a notification should not be generated for check 'abc' on entity 'def'

  @time
  Scenario: Check ok to failed for 1 minute when in unscheduled maintenance
    Given check 'abc' for entity 'def' is in an ok state
    And   check 'abc' for entity 'def' is in unscheduled maintenance
    When  a failure event is received for check 'abc' on entity 'def'
    And   1 minute passes
    And   a failure event is received for check 'abc' on entity 'def'
    Then  a notification should not be generated for check 'abc' on entity 'def'

  @time
  Scenario: Check ok to failed for 1 minute, acknowledged, and failed for 6 minutes
    Given check 'abc' for entity 'def' is in an ok state
    When  a failure event is received for check 'abc' on entity 'def'
    And   1 minute passes
    And   a failure event is received for check 'abc' on entity 'def'
    Then  a notification should be generated for check 'abc' on entity 'def'
    When  an acknowledgement is received for check 'abc' on entity 'def'
    And   6 minute passes
    And   a failure event is received for check 'abc' on entity 'def'
    Then  a notification should not be generated for check 'abc' on entity 'def'

  Scenario: Check failed to ok
    Given check 'abc' for entity 'def' is in a failure state
    And   5 minutes passes
    And   a failure event is received for check 'abc' on entity 'def'
    Then  a notification should be generated for check 'abc' on entity 'def'
    When  5 minutes passes
    And   an ok event is received for check 'abc' on entity 'def'
    Then  a notification should be generated for check 'abc' on entity 'def'

  @time
  Scenario: Check failed to ok when acknowledged
    Given check 'abc' for entity 'def' is in a failure state
    When  an acknowledgement event is received for check 'abc' on entity 'def'
    Then  a notification should be generated for check 'abc' on entity 'def'
    When  1 minute passes
    And   an ok event is received for check 'abc' on entity 'def'
    Then  a notification should be generated for check 'abc' on entity 'def'

  @time
  Scenario: Check failed to ok when acknowledged, and fails after 6 minutes
    Given check 'abc' for entity 'def' is in a failure state
    When  an acknowledgement event is received for check 'abc' on entity 'def'
    Then  a notification should be generated for check 'abc' on entity 'def'
    When  1 minute passes
    And   an ok event is received for check 'abc' on entity 'def'
    Then  a notification should be generated for check 'abc' on entity 'def'
    When  6 minutes passes
    And   a failure event is received for check 'abc' on entity 'def'
    Then  a notification should not be generated for check 'abc' on entity 'def'
    When  6 minutes passes
    And   a failure event is received for check 'abc' on entity 'def'
    Then  a notification should be generated for check 'abc' on entity 'def'

  @time
  Scenario: Osciliating state, period of two minutes
    Given check 'abc' for entity 'def' is in an ok state
    When  a failure event is received for check 'abc' on entity 'def'
    Then  a notification should not be generated for check 'abc' on entity 'def'
    When  50 seconds passes
    And   a failure event is received for check 'abc' on entity 'def'
    Then  a notification should be generated for check 'abc' on entity 'def'
    When  10 seconds passes
    And   an ok event is received for check 'abc' on entity 'def'
    Then  a notification should be generated for check 'abc' on entity 'def'
    When  50 seconds passes
    And   an ok event is received for check 'abc' on entity 'def'
    Then  a notification should not be generated for check 'abc' on entity 'def'
    When  10 seconds passes
    And   a failure event is received for check 'abc' on entity 'def'
    Then  a notification should not be generated for check 'abc' on entity 'def'
    When  50 seconds passes
    And   a failure event is received for check 'abc' on entity 'def'
    #And   show me the notifications
    Then  a notification should be generated for check 'abc' on entity 'def'
    When  10 seconds passes
    And   an ok event is received for check 'abc' on entity 'def'
    Then  a notification should be generated for check 'abc' on entity 'def'

  Scenario: Acknowledgement when ok
    Given check 'abc' for entity 'def' is in an ok state
    When  an acknowledgement event is received for check 'abc' on entity 'def'
    Then  a notification should not be generated for check 'abc' on entity 'def'

  Scenario: Acknowledgement when failed
    Given check 'abc' for entity 'def' is in a failure state
    When  an acknowledgement event is received for check 'abc' on entity 'def'
    Then  a notification should be generated for check 'abc' on entity 'def'

  Scenario: Brief failure then OK
    Given check 'abc' for entity 'def' is in an ok state
    When  a failure event is received for check 'abc' on entity 'def'
    And   10 seconds passes
    And   an ok event is received for check 'abc' on entity 'def'
    Then  a notification should not be generated for check 'abc' on entity 'def'

  Scenario: Flapper (down for one minute, up for one minute, repeat)
    Given check 'abc' for entity 'def' is in an ok state
    When  a failure event is received for check 'abc' on entity 'def'
    Then  a notification should not be generated for check 'abc' on entity 'def'
    When  10 seconds passes
    And   a failure event is received for check 'abc' on entity 'def'
    Then  a notification should not be generated for check 'abc' on entity 'def'
    When  10 seconds passes
    And   a failure event is received for check 'abc' on entity 'def'
    Then  a notification should not be generated for check 'abc' on entity 'def'
    When  10 seconds passes
    # 30 seconds
    And   a failure event is received for check 'abc' on entity 'def'
    Then  a notification should be generated for check 'abc' on entity 'def'
    When  10 seconds passes
    And   a failure event is received for check 'abc' on entity 'def'
    Then  a notification should not be generated for check 'abc' on entity 'def'
    When  10 seconds passes
    And   a failure event is received for check 'abc' on entity 'def'
    Then  a notification should not be generated for check 'abc' on entity 'def'
    When  10 seconds passes
    # 60 seconds
    And   an ok event is received for check 'abc' on entity 'def'
    Then  a notification should be generated for check 'abc' on entity 'def'
    When  10 seconds passes
    And   an ok event is received for check 'abc' on entity 'def'
    Then  a notification should not be generated for check 'abc' on entity 'def'
    When  10 seconds passes
    And   an ok event is received for check 'abc' on entity 'def'
    Then  a notification should not be generated for check 'abc' on entity 'def'
    When  10 seconds passes
    And   an ok event is received for check 'abc' on entity 'def'
    Then  a notification should not be generated for check 'abc' on entity 'def'
    When  10 seconds passes
    And   an ok event is received for check 'abc' on entity 'def'
    Then  a notification should not be generated for check 'abc' on entity 'def'
    When  10 seconds passes
    And   an ok event is received for check 'abc' on entity 'def'
    Then  a notification should not be generated for check 'abc' on entity 'def'
    When  10 seconds passes
    # 120 seconds
    And   a failure event is received for check 'abc' on entity 'def'
    Then  a notification should not be generated for check 'abc' on entity 'def'
    When  10 seconds passes
    And   a failure event is received for check 'abc' on entity 'def'
    Then  a notification should not be generated for check 'abc' on entity 'def'
    When  10 seconds passes
    And   a failure event is received for check 'abc' on entity 'def'
    Then  a notification should not be generated for check 'abc' on entity 'def'
    When  10 seconds passes
    # 150 seconds
    And   a failure event is received for check 'abc' on entity 'def'
    Then  a notification should be generated for check 'abc' on entity 'def'
    When  10 seconds passes
    And   a failure event is received for check 'abc' on entity 'def'
    Then  a notification should not be generated for check 'abc' on entity 'def'
    When  10 seconds passes
    And   a failure event is received for check 'abc' on entity 'def'
    Then  a notification should not be generated for check 'abc' on entity 'def'
    When  10 seconds passes
    # 180 seconds
    And   an ok event is received for check 'abc' on entity 'def'
    Then  a notification should be generated for check 'abc' on entity 'def'
