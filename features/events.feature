@events @processor
Feature: events
  So people can be notified when things break and recover
  flapjack-executive must process events correctly

  Background:
    Given an entity 'foo-app-01.example.com' exists
    And the check is check 'HTTP Port 80' on entity 'foo-app-01.example.com'

  Scenario: Check ok to ok
    Given the check is in an ok state
    When  an ok event is received
    Then  a notification should not be generated

  Scenario: Check ok to warning
    Given the check is in an ok state
    When  a warning event is received
    Then  a notification should not be generated

  Scenario: Check ok to critical
    Given the check is in an ok state
    When  a critical event is received
    Then  a notification should not be generated

  @time
  Scenario: Check critical to critical after 10 seconds
    Given the check is in an ok state
    When  a critical event is received
    And   10 seconds passes
    And   a critical event is received
    Then  a notification should not be generated

  @time
  Scenario: Check ok to warning for 1 minute
    Given the check is in an ok state
    When  a warning event is received
    And   1 minute passes
    And   a warning event is received
    Then  a notification should be generated

  @time
  Scenario: Check ok to critical for 1 minute
    Given the check is in an ok state
    When  a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  a notification should be generated

  @time
  Scenario: Check ok to warning, 1 min, then critical
    Given the check is in an ok state
    When  a warning event is received
    And   1 minute passes
    And   a warning event is received
    Then  a notification should be generated
    When  a critical event is received
    Then  a notification should not be generated
    When  1 minute passes
    And   a critical event is received
    Then  a notification should be generated

  @time
  Scenario: Check critical and alerted to critical for 40 seconds
    Given the check is in an ok state
    When  a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  a notification should be generated
    When  40 seconds passes
    And   a critical event is received
    Then  a notification should not be generated

  @time
  Scenario: Check critical and alerted to critical for 6 minutes
    Given the check is in an ok state
    When  a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  a notification should be generated
    When  6 minutes passes
    And   a critical event is received
    Then  a notification should be generated

  @time
  Scenario: Check ok to critical for 1 minute when in scheduled maintenance
    Given the check is in an ok state
    And   the check is in scheduled maintenance
    When  a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  a notification should not be generated

  @time
  Scenario: Alert when coming out of scheduled maintenance
    Given the check is in an ok state
    And   the check is in scheduled maintenance for 3 hours
    When  a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  a notification should not be generated
    And   2 hours passes
    And   a critical event is received
    Then  a notification should not be generated
    When  1 hours passes
    And   a critical event is received
    Then  a notification should be generated

  @time
  Scenario: Check ok to critical for 1 minute when in unscheduled maintenance
    Given the check is in an ok state
    And   the check is in unscheduled maintenance
    When  a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  a notification should not be generated

  @time
  Scenario: Check ok to critical for 1 minute, acknowledged, and critical for 6 minutes
    Given the check is in an ok state
    When  a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  a notification should be generated
    When  an acknowledgement event is received
    And   6 minute passes
    And   a critical event is received
    Then  a notification should not be generated

  @time
  Scenario: Check critical to ok
    Given the check is in a critical state
    When  5 minutes passes
    And   a critical event is received
    Then  a notification should be generated
    When  5 minutes passes
    And   an ok event is received
    Then  a notification should be generated

  @time
  Scenario: Check critical to ok when acknowledged
    Given the check is in an ok state
    When  a critical event is received
    And   one minute passes
    And   a critical event is received
    Then  a notification should be generated
    # the above all needs to be just a call to the "Check ok to critical for 1 minute" Scenario if that's possible
    When  an acknowledgement event is received
    Then  a notification should be generated
    When  1 minute passes
    And   an ok event is received
    Then  a notification should be generated

  @time
  Scenario: Check critical to ok when acknowledged, and fails after 6 minutes
    Given the check is in a critical state
    When  an acknowledgement event is received
    Then  a notification should be generated
    When  1 minute passes
    And   an ok event is received
    Then  a notification should be generated
    When  6 minutes passes
    And   a critical event is received
    Then  a notification should not be generated
    When  6 minutes passes
    And   a critical event is received
    Then  a notification should be generated

  @time
  Scenario: Osciliating state, period of two minutes
    Given the check is in an ok state
    When  a critical event is received
    # No notification because initial delay
    Then  a notification should not be generated

    When  50 seconds passes
    And   a critical event is received
    Then  a notification should be generated
    When  10 seconds passes
    And   an ok event is received
    Then  a notification should be generated
    When  50 seconds passes
    And   an ok event is received
    Then  a notification should not be generated
    When  10 seconds passes
    And   a critical event is received
    Then  a notification should not be generated
    When  50 seconds passes
    And   a critical event is received
    Then  a notification should be generated
    When  10 seconds passes
    And   an ok event is received
    Then  a notification should be generated

  Scenario: Acknowledgement when ok
    Given the check is in an ok state
    When  an acknowledgement event is received
    Then  a notification should not be generated

  Scenario: Acknowledgement when critical
    Given the check is in a critical state
    When  an acknowledgement event is received
    Then  a notification should be generated

  Scenario: Acknowledgement when acknowledged
    Given the check is in a critical state
    When  an acknowledgement event is received
    Then  a notification should be generated
    When  an acknowledgement event is received
    Then  a notification should be generated

  Scenario: Brief critical then OK
    Given the check is in an ok state
    When  a critical event is received
    And   10 seconds passes
    And   an ok event is received
    Then  a notification should not be generated

  @time
  Scenario: Quick stream of unknown
    Given the check is in an ok state
    When  a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  a notification should be generated
    When  10 minutes passes
    And   an unknown event is received
    Then  a notification should not be generated
    When  60 seconds passes
    And   an unknown event is received
    Then  a notification should be generated
    When  10 seconds passes
    And   an unknown event is received
    Then  a notification should not be generated
    When  10 seconds passes
    And   an unknown event is received
    Then  a notification should not be generated
    When  10 seconds passes
    And   an unknown event is received
    Then  a notification should not be generated
    When  10 seconds passes
    And   an unknown event is received
    Then  a notification should not be generated
    When  10 seconds passes
    And   an unknown event is received
    Then  a notification should not be generated
    When  1 minutes passes
    And   an unknown event is received
    Then  a notification should be generated
    When  10 seconds passes
    And   an unknown event is received
    Then  a notification should not be generated
    When  10 seconds passes
    And   an unknown event is received
    Then  a notification should not be generated
    When  10 seconds passes
    And   an unknown event is received
    Then  a notification should not be generated

  @time
  Scenario: Flapper (down for one minute, up for one minute, repeat)
    Given the check is in an ok state
    When  a critical event is received
    Then  a notification should not be generated
    When  10 seconds passes
    And   a critical event is received
    Then  a notification should not be generated
    When  10 seconds passes
    And   a critical event is received
    Then  a notification should not be generated
    When  10 seconds passes
    # 30 seconds
    And   a critical event is received
    Then  a notification should be generated
    When  10 seconds passes
    And   a critical event is received
    Then  a notification should not be generated
    When  10 seconds passes
    And   a critical event is received
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
    And   a critical event is received
    Then  a notification should not be generated
    When  10 seconds passes
    And   a critical event is received
    Then  a notification should not be generated
    When  10 seconds passes
    And   a critical event is received
    Then  a notification should not be generated
    When  10 seconds passes
    # 150 seconds
    And   a critical event is received
    Then  a notification should be generated
    When  10 seconds passes
    And   a critical event is received
    Then  a notification should not be generated
    When  10 seconds passes
    And   a critical event is received
    Then  a notification should not be generated
    When  10 seconds passes
    # 180 seconds
    And   an ok event is received
    Then  a notification should be generated

# commenting out this test for now, will revive it
# when working on gh-119
@time
Scenario: a lot of quick ok -> warning -> ok -> warning
     Given the check is in an ok state
     When  10 seconds passes
     And   a warning event is received
     Then  a notification should not be generated
     When  10 seconds passes
     And   an ok event is received
     Then  a notification should not be generated
     When  10 seconds passes
     And   a warning event is received
     Then  a notification should not be generated
     When  10 seconds passes
     And   a warning event is received
     Then  a notification should not be generated
     When  10 seconds passes
     And   a warning event is received
     Then  a notification should not be generated
     When  20 seconds passes
     And   an ok event is received
     Then  a notification should not be generated
     When  10 seconds passes
     And   a warning event is received
     Then  a notification should not be generated
     When  10 seconds passes
     And   an ok event is received
     Then  a notification should not be generated
     When  10 seconds passes
     And   a warning event is received
     Then  a notification should not be generated
     When  10 seconds passes
     And   a warning event is received
     Then  a notification should not be generated
     When  10 seconds passes
     And   a warning event is received
     Then  a notification should not be generated
     When  10 seconds passes
     And   a warning event is received
     Then  a notification should be generated
     When  10 seconds passes
     And   a warning event is received
     Then  a notification should not be generated
     When  10 seconds passes
     And   a warning event is received
     Then  a notification should not be generated
     When  10 seconds passes
     And   an ok event is received
     Then  a notification should be generated
     # recovered
     When  10 seconds passes
     And   a warning event is received
     Then  a notification should not be generated
     When  10 seconds passes
     And   a warning event is received
     Then  a notification should not be generated
     When  10 seconds passes
     And   a warning event is received
     Then  a notification should not be generated
     When  10 seconds passes
     And   an ok event is received
     Then  a notification should not be generated
     When  10 seconds passes
     And   a warning event is received
     Then  a notification should not be generated
     When  10 seconds passes
     And   a warning event is received
     Then  a notification should not be generated
     When  10 seconds passes
     And   a warning event is received
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
     And   an ok event is received
     Then  a notification should not be generated
     When  10 seconds passes
     And   a warning event is received
     Then  a notification should not be generated
     When  10 seconds passes
     And   a warning event is received
     Then  a notification should not be generated
     When  10 seconds passes
     And   an ok event is received
     Then  a notification should not be generated

  Scenario: scheduled maintenance created for initial check reference
    Given the check has no state
    When  an ok event is received
    Then  scheduled maintenance should be generated

@time
Scenario: a transient recovery
    Given event initial recovery delay 30 seconds
    Given the check is in a critical state
    When  10 seconds passes
    And   a critical event is received with details 'event 1: critical'
    Then  a notification should be generated

    When  5 seconds passes
    And   an ok event is received with details 'event 2: ok - no event, before initial_recovery_delay'
    Then  a notification should not be generated

    When  5 seconds passes
    And   an ok event is received with details 'event 3: ok - no event, still before initial_recovery_delay'
    Then  a notification should not be generated

    When 10 seconds passes
    And  a critical event is received with details 'event 4: critical, no event because we were in the initial_failure_delay'
    Then  a notification should not be generated

    When 30 seconds passes
    And  a critical event is received with details 'event 5: critical, no event because we are in the repeat_failure_delay'
    Then  a notification should not be generated

    When 10 seconds passes
    And   an ok event is received with details 'event 6: ok - no event, before initial_recovery_delay'
    Then  a notification should not be generated

    When 60 seconds passes
    And   an ok event is received with details 'event 7: ok - send event, after initial_recovery_delay'
    Then  a notification should be generated

    When 60 seconds passes
    And   an ok event is received with details 'event 8: ok - no event, we have already sent the recovery'
    Then  a notification should not be generated
