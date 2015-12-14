@events @processor
Feature: events
  So people can be notified when things break and recover
  flapjack-executive must process events correctly

  Background:
    Given the check is check 'HTTP Port 80' on entity 'foo-app-01.example.com'

  Scenario: Check ok to ok
    Given the check is in an ok state
    When  an ok event is received
    Then  no notifications should have been generated

  Scenario: Check ok to warning
    Given the check is in an ok state
    When  a warning event is received
    Then  no notifications should have been generated

  Scenario: Check ok to critical
    Given the check is in an ok state
    When  a critical event is received
    Then  no notifications should have been generated

  @time
  Scenario: Check critical to critical after 10 seconds
    Given the check is in an ok state
    When  a critical event is received
    And   10 seconds passes
    And   a critical event is received
    Then  no notifications should have been generated

  @time
  Scenario: Check critical to critical after 10 seconds, with an initial delay of 5 seconds
    Given event initial failure delay is 5 seconds
    And   the check is in an ok state
    When  a critical event is received
    And   10 seconds passes
    And   a critical event is received
    Then  1 notification should have been generated

  @time
  Scenario: Check recovery with recovery delay
    Given event initial recovery delay is 30 seconds
    And   the check is in an ok state
    When  a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  1 notification should have been generated
    When  10 seconds passes
    And   an ok event is received
    Then  1 notification should have been generated
    When  10 seconds passes
    And   an ok event is received
    Then  1 notification should have been generated
    When  25 seconds passes
    And   an ok event is received
    Then  2 notifications should have been generated

  @time
  Scenario: Check ok to warning for 1 minute
    Given the check is in an ok state
    When  a warning event is received
    And   1 minute passes
    And   a warning event is received
    Then  1 notification should have been generated

  @time
  Scenario: Check ok to critical for 1 minute
    Given the check is in an ok state
    When  a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  1 notification should have been generated

  @time
  Scenario: Check ok to critical for 1 minute, with an initial delay of 2 minutes
    Given event initial failure delay is 120 seconds
    And   the check is in an ok state
    When  a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  no notifications should have been generated

  @time
  Scenario: Check ok to warning, 45 seconds, then critical
    Given the check is in an ok state
    When  a warning event is received
    And   1 minute passes
    And   a warning event is received
    Then  1 notification should have been generated
    And   45 seconds passes
    When  a critical event is received
    Then  1 notification should have been generated
    When  1 minute passes
    And   a critical event is received
    Then  2 notifications should have been generated

  @time
  Scenario: Check critical and alerted to critical for 40 seconds
    Given the check is in an ok state
    When  a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  1 notification should have been generated
    When  40 seconds passes
    And   a critical event is received
    Then  1 notification should have been generated

  @time
  Scenario: Check critical and alerted to critical for 40 seconds, with a repeat delay of 20 seconds
    Given event repeat failure delay is 20 seconds
    And the check is in an ok state
    When  a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  1 notification should have been generated
    When  40 seconds passes
    And   a critical event is received
    Then  2 notifications should have been generated

  @time
  Scenario: Check critical and alerted to critical for 6 minutes
    Given the check is in an ok state
    When  a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  1 notification should have been generated
    When  6 minutes passes
    And   a critical event is received
    Then  2 notifications should have been generated

  @time
  Scenario: Check critical and alerted to critical for 6 minutes, with a repeat delay of 10 minutes
    Given event repeat failure delay is 600 seconds
    And the check is in an ok state
    When  a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  1 notification should have been generated
    When  6 minutes passes
    And   a critical event is received
    Then  1 notification should have been generated

  @time
  Scenario: Check ok to critical for 1 minute when in scheduled maintenance
    Given the check is in an ok state
    And   the check is in scheduled maintenance
    When  a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  no notifications should have been generated

  @time
  Scenario: Alert when coming out of scheduled maintenance
    Given the check is in an ok state
    And   the check is in scheduled maintenance for 3 hours
    When  a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  no notifications should have been generated
    And   2 hours passes
    And   a critical event is received
    Then  no notifications should have been generated
    When  1 hours passes
    And   a critical event is received
    Then  1 notification should have been generated

  @time
  Scenario: Check ok to critical for 1 minute when in unscheduled maintenance
    Given the check is in an ok state
    And   the check is in unscheduled maintenance
    When  a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  no notifications should have been generated

  @time
  Scenario: Check ok to critical for 1 minute, acknowledged, and critical for 6 minutes
    Given the check is in an ok state
    When  a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  1 notification should have been generated
    When  an acknowledgement event is received
    Then  2 notifications should have been generated
    And   6 minute passes
    And   a critical event is received
    Then  2 notifications should have been generated

  @time
  Scenario: Check critical to ok
    Given the check is in a critical state
    When  5 minutes passes
    And   a critical event is received
    Then  1 notification should have been generated
    When  5 minutes passes
    And   an ok event is received
    Then  2 notifications should have been generated

  @time
  Scenario: Check critical to ok when acknowledged
    Given the check is in an ok state
    When  a critical event is received
    And   one minute passes
    And   a critical event is received
    Then  1 notification should have been generated
    And   one minute passes
    When  an acknowledgement event is received
    Then  2 notifications should have been generated
    When  1 minute passes
    And   an ok event is received
    Then  3 notifications should have been generated

  @time
  Scenario: Check critical to ok when acknowledged, and fails after 6 minutes
    Given the check is in a critical state
    When  an acknowledgement event is received
    Then  1 notification should have been generated
    When  1 minute passes
    And   an ok event is received
    Then  2 notifications should have been generated
    When  6 minutes passes
    And   a critical event is received
    And   45 seconds passes
    And   a critical event is received
    Then  3 notifications should have been generated
    When  6 minutes passes
    And   a critical event is received
    Then  4 notifications should have been generated

  @time
  Scenario: Oscillating state, period of two minutes
    Given the check is in an ok state
    When  a critical event is received
    Then  no notifications should have been generated
    When  50 seconds passes
    And   a critical event is received
    Then  1 notification should have been generated
    When  10 seconds passes
    And   an ok event is received
    Then  2 notifications should have been generated
    When  50 seconds passes
    And   an ok event is received
    Then  2 notifications should have been generated
    When  10 seconds passes
    And   a critical event is received
    And   45 seconds passes
    And   a critical event is received
    Then  3 notifications should have been generated
    When  50 seconds passes
    And   a critical event is received
    Then  3 notifications should have been generated
    When  10 seconds passes
    And   an ok event is received
    Then  4 notifications should have been generated

  Scenario: Acknowledgement when ok
    Given the check is in an ok state
    When  an acknowledgement event is received
    Then  no notifications should have been generated

  Scenario: Acknowledgement when critical
    Given the check is in a critical state
    When  an acknowledgement event is received
    Then  1 notification should have been generated

  Scenario: Brief critical then OK
    Given the check is in an ok state
    When  a critical event is received
    And   10 seconds passes
    And   an ok event is received
    Then  no notifications should have been generated

  @time
  Scenario: Quick stream of unknown
    Given the check is in an ok state
    When  a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  1 notification should have been generated
    When  10 minutes passes
    And   an unknown event is received
    Then  2 notifications should have been generated
    When  60 seconds passes
    And   an unknown event is received
    Then  3 notifications should have been generated
    When  10 seconds passes
    And   an unknown event is received
    Then  3 notifications should have been generated
    When  10 seconds passes
    And   an unknown event is received
    Then  3 notifications should have been generated
    When  10 seconds passes
    And   an unknown event is received
    Then  3 notifications should have been generated
    When  10 seconds passes
    And   an unknown event is received
    Then  3 notifications should have been generated
    When  10 seconds passes
    And   an unknown event is received
    Then  3 notifications should have been generated
    When  1 minutes passes
    And   an unknown event is received
    Then  4 notifications should have been generated
    When  10 seconds passes
    And   an unknown event is received
    Then  4 notifications should have been generated
    When  10 seconds passes
    And   an unknown event is received
    Then  4 notifications should have been generated
    When  10 seconds passes
    And   an unknown event is received
    Then  4 notifications should have been generated

  @time
  Scenario: Flapper (down for one minute, up for one minute, repeat)
    Given the check is in an ok state
    When  a critical event is received
    Then  no notifications should have been generated
    When  10 seconds passes
    And   a critical event is received
    Then  no notifications should have been generated
    When  10 seconds passes
    And   a critical event is received
    Then  no notifications should have been generated
    When  10 seconds passes
    # 30 seconds
    And   a critical event is received
    Then  1 notification should have been generated
    When  10 seconds passes
    And   a critical event is received
    Then  1 notification should have been generated
    When  10 seconds passes
    And   a critical event is received
    Then  1 notification should have been generated
    When  10 seconds passes
    # 60 seconds
    And   an ok event is received
    Then  2 notifications should have been generated
    When  10 seconds passes
    And   an ok event is received
    Then  2 notifications should have been generated
    When  10 seconds passes
    And   an ok event is received
    Then  2 notifications should have been generated
    When  10 seconds passes
    And   an ok event is received
    Then  2 notifications should have been generated
    When  10 seconds passes
    And   an ok event is received
    Then  2 notifications should have been generated
    When  10 seconds passes
    And   an ok event is received
    Then  2 notifications should have been generated
    When  10 seconds passes
    # 120 seconds
    And   a critical event is received
    And   45 seconds passes
    And   a critical event is received
    Then  3 notifications should have been generated
    When  10 seconds passes
    And   a critical event is received
    Then  3 notifications should have been generated
    When  10 seconds passes
    And   a critical event is received
    Then  3 notifications should have been generated
    When  10 seconds passes
    # 150 seconds
    And   a critical event is received
    Then  3 notifications should have been generated
    When  10 seconds passes
    And   a critical event is received
    Then  3 notifications should have been generated
    When  10 seconds passes
    And   a critical event is received
    Then  3 notifications should have been generated
    When  10 seconds passes
    # 180 seconds
    And   an ok event is received
    Then  4 notifications should have been generated

@time
Scenario: a lot of quick ok -> warning -> ok -> warning
    Given the check is in an ok state
    When  10 seconds passes
    And   a warning event is received
    Then  no notifications should have been generated
    When  10 seconds passes
    And   an ok event is received
    Then  no notifications should have been generated
    When  10 seconds passes
    And   a warning event is received
    Then  no notifications should have been generated
    When  10 seconds passes
    And   a warning event is received
    Then  no notifications should have been generated
    When  10 seconds passes
    And   a warning event is received
    Then  no notifications should have been generated
    When  20 seconds passes
    And   an ok event is received
    Then  no notifications should have been generated
    When  10 seconds passes
    And   a warning event is received
    Then  no notifications should have been generated
    When  10 seconds passes
    And   an ok event is received
    Then  no notifications should have been generated
    When  10 seconds passes
    And   a warning event is received
    Then  no notifications should have been generated
    When  10 seconds passes
    And   a warning event is received
    Then  no notifications should have been generated
    When  10 seconds passes
    And   a warning event is received
    Then  no notifications should have been generated
    When  10 seconds passes
    And   a warning event is received
    Then  1 notification should have been generated
    When  10 seconds passes
    And   a warning event is received
    Then  1 notification should have been generated
    When  10 seconds passes
    And   a warning event is received
    Then  1 notification should have been generated
    When  10 seconds passes
    And   an ok event is received
    Then  2 notifications should have been generated
    # recovered
    When  10 seconds passes
    And   a warning event is received
    Then  2 notifications should have been generated
    When  10 seconds passes
    And   a warning event is received
    Then  2 notifications should have been generated
    When  10 seconds passes
    And   a warning event is received
    Then  2 notifications should have been generated
    When  10 seconds passes
    And   an ok event is received
    Then  2 notifications should have been generated
    When  10 seconds passes
    And   a warning event is received
    Then  2 notifications should have been generated
    When  10 seconds passes
    And   a warning event is received
    Then  2 notifications should have been generated
    When  10 seconds passes
    And   a warning event is received
    Then  2 notifications should have been generated
    When  10 seconds passes
    And   an ok event is received
    Then  2 notifications should have been generated
    When  10 seconds passes
    And   an ok event is received
    Then  2 notifications should have been generated
    When  10 seconds passes
    And   an ok event is received
    Then  2 notifications should have been generated
    When  10 seconds passes
    And   an ok event is received
    Then  2 notifications should have been generated
    When  10 seconds passes
    And   an ok event is received
    Then  2 notifications should have been generated
    When  10 seconds passes
    And   a warning event is received
    And   45 seconds passes
    And   a warning event is received
    Then  3 notifications should have been generated
    When  10 seconds passes
    And   a warning event is received
    Then  3 notifications should have been generated
    When  10 seconds passes
    And   an ok event is received
    Then  4 notifications should have been generated

  @time
  Scenario: a transient recovery
    Given event initial recovery delay is 30 seconds
    Given the check is in a critical state
    When  35 seconds passes
    # 'event 1: critical'
    And   a critical event is received
    Then  1 notification should have been generated

    When  5 seconds passes
    # 'event 2: ok - no event, before initial_recovery_delay'
    And   an ok event is received
    Then  1 notification should have been generated

    When  5 seconds passes
    # 'event 3: ok - no event, still before initial_recovery_delay'
    And   an ok event is received
    Then  1 notification should have been generated

    When 10 seconds passes
    # 'event 4: critical, no event because we were in the initial_failure_delay'
    And  a critical event is received
    Then  1 notification should have been generated

    When 30 seconds passes
    # 'event 5: critical, no event because we are in the repeat_failure_delay'
    And  a critical event is received
    Then  1 notification should have been generated

    When 10 seconds passes
    # 'event 6: ok - no event, before initial_recovery_delay'
    And   an ok event is received
    Then  1 notification should have been generated

    When 60 seconds passes
    # 'event 7: ok - send event, after initial_recovery_delay'
    And   an ok event is received
    Then  2 notifications should have been generated

    When 60 seconds passes
    # 'event 8: ok - no event, we have already sent the recovery'
    And   an ok event is received
    Then  2 notifications should have been generated
