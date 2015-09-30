@rollup @notification_rules @processor @notifier @events
Feature: Rollup on a per contact, per media basis

  Background:
    Given the following users exist:
      | id  | first_name | last_name | email             | sms          | timezone         |
      | 1   | Malak      | Al-Musawi | malak@example.com | +61400000001 | Asia/Baghdad     |

    And the following entities exist:
      | id  | name           | contacts |
      | 1   | foo            | 1        |
      | 2   | baz            | 1        |
      | 3   | zoo            | 1        |

    And user 1 has the following notification intervals:
      | email | sms |
      | 15    | 15  |

    And user 1 has the following notification rollup thresholds:
      | email | sms |
      | 1     | 2   |

    And user 1 has the following notification rules:
      | entities | unknown_media | warning_media | critical_media   |
      |          |               | email         | sms,email        |

  @time
  Scenario: Rollup threshold of 1 means first alert is a rollup
    Given the check is check 'ping' on entity 'foo'
    And   the check is in an ok state
    When  a critical event is received
    Then  no email alerts should be queued for malak@example.com
    When  1 minute passes
    And   a critical event is received
    Then  1 email alert of type problem and rollup problem should be queued for malak@example.com
    When  1 minute passes
    And   an ok event is received
    Then  1 email alert of type recovery and rollup recovery should be queued for malak@example.com

  @time
  Scenario: Acknowledgement ending rollup generates rollup recovery message ignoring interval
    Given the check is check 'ping' on entity 'foo'
    And   the check is in an ok state
    When  a critical event is received
    Then  no email alerts should be queued for malak@example.com
    When  1 minute passes
    And   a critical event is received
    Then  1 email alert of type problem and rollup problem should be queued for malak@example.com
    When  10 minutes passes
    And   an acknowledgement event is received
    Then  1 email alert of rollup recovery should be queued for malak@example.com
    And   2 email alerts should be queued for malak@example.com

  @time
  Scenario: Transition to rollup when threshold is met
    Given check 'ping' for entity 'foo' is in an ok state
    And   check 'ping' for entity 'baz' is in an ok state
    When  a critical event is received for check 'ping' on entity 'foo' with details 'event 1 - no alert due to delay'
    Then  no sms alerts should be queued for +61400000001
    When  1 minute passes
    And   a critical event is received for check 'ping' on entity 'foo' with details 'event 2 - gen alert'
    Then  1 sms alert of type problem and rollup none should be queued for +61400000001
    When  5 minutes passes
    And   a critical event is received for check 'ping' on entity 'baz' with details 'event 3 - no alert due to delay'
    And   1 minute passes
    And   a critical event is received for check 'ping' on entity 'baz' with details 'event 4 - alert, SMS to rollup'
    Then  1 sms alert of type problem and rollup none should be queued for +61400000001
    And   1 sms alert of type problem and rollup problem should be queued for +61400000001
    When  1 minute passes
    And   an ok event is received for check 'ping' on entity 'foo' with details 'event 5'
    Then  no sms alerts of type recovery and rollup none should be queued for +61400000001
    And   1 sms alert of type recovery and rollup recovery should be queued for +61400000001
    And   3 sms alerts should be queued for +61400000001
    When  1 minute passes
    And   an ok event is received for check 'ping' on entity 'baz' with details 'event 6'
    Then  1 sms alert of type recovery and rollup none should be queued for +61400000001
    And   1 sms alert of type recovery and rollup recovery should be queued for +61400000001
    And   4 sms alerts should be queued for +61400000001

  @time
  Scenario: Acknowledgement delays rollup kick-in
    Given check 'ping' for entity 'foo' is in an ok state
    And   check 'ping' for entity 'baz' is in an ok state
    When  a critical event is received for check 'ping' on entity 'foo'
    Then  no sms alerts should be queued for +61400000001
    When  1 minute passes
    And   a critical event is received for check 'ping' on entity 'foo'
    Then  1 sms alert of type problem and rollup none should be queued for +61400000001
    When  5 minutes passes
    And   an acknowledgement event is received for check 'ping' on entity 'foo'
    Then  1 sms alert of type acknowledgement and rollup none should be queued for +61400000001
    And   2 sms alerts should be queued for +61400000001
    When  a critical event is received for check 'ping' on entity 'baz'
    And   1 minute passes
    And   a critical event is received for check 'ping' on entity 'baz'
    Then  2 sms alerts of type problem and rollup none should be queued for +61400000001
    And   3 sms alerts should be queued for +61400000001

  @time
  Scenario: Acknowledgement hastens rollup recovery
    Given check 'ping' for entity 'foo' is in an ok state
    And   check 'ping' for entity 'baz' is in an ok state
    When  a critical event is received for check 'ping' on entity 'foo'
    And   1 minute passes
    And   a critical event is received for check 'ping' on entity 'foo'
    Then  1 sms alerts of type problem and rollup none should be queued for +61400000001
    When  5 minutes passes
    And   a critical event is received for check 'ping' on entity 'baz'
    And   1 minute passes
    And   a critical event is received for check 'ping' on entity 'baz'
    Then  1 sms alert of type problem and rollup problem should be queued for +61400000001
    And   2 sms alerts should be queued for +61400000001
    When  an acknowledgement event is received for check 'ping' on entity 'foo'
    Then  1 sms alert of type acknowledgement and rollup recovery should be queued for +61400000001
    And   3 sms alerts should be queued for +61400000001
    When  30 minutes passes
    And   a critical event is received for check 'ping' on entity 'baz'
    Then  2 sms alerts of type problem and rollup none should be queued for +61400000001
    And   4 sms alerts should be queued for +61400000001

  @time
  Scenario: Scheduled maintenance hastens rollup recovery
    Given check 'ping' for entity 'foo' is in an ok state
    And   check 'ping' for entity 'baz' is in an ok state
    When  a critical event is received for check 'ping' on entity 'foo'
    And   1 minute passes
    And   a critical event is received for check 'ping' on entity 'foo'
    Then  1 sms alerts of type problem and rollup none should be queued for +61400000001
    When  5 minutes passes
    And   a critical event is received for check 'ping' on entity 'baz'
    And   1 minute passes
    And   a critical event is received for check 'ping' on entity 'baz'
    Then  1 sms alert of type problem and rollup problem should be queued for +61400000001
    And   2 sms alerts should be queued for +61400000001
    When  check 'ping' for entity 'foo' is in scheduled maintenance for 1 day
    And   30 minutes passes
    And   a critical event is received for check 'ping' on entity 'baz'
    Then  1 sms alert of rollup recovery should be queued for +61400000001

  @time
  Scenario: Unscheduled maintenance ending promotes rollup
    Given check 'ping' for entity 'foo' is in unscheduled maintenance
    And   check 'ping' for entity 'baz' is in an ok state
    When  a critical event is received for check 'ping' on entity 'foo'
    And   1 minute passes
    And   a critical event is received for check 'ping' on entity 'foo'
    Then  0 sms alerts should be queued for +61400000001
    When  5 minutes passes
    And   a critical event is received for check 'ping' on entity 'baz'
    And   1 minute passes
    And   a critical event is received for check 'ping' on entity 'baz'
    Then  1 sms alert of type problem and rollup none should be queued for +61400000001
    And   1 sms alerts should be queued for +61400000001
    When  4 hours passes
    And   a critical event is received for check 'ping' on entity 'foo'
    Then  1 sms alert of type problem and rollup problem should be queued for +61400000001
    And   2 sms alerts should be queued for +61400000001

  @time
  Scenario: Scheduled maintenance ending promotes rollup
    Given check 'ping' for entity 'foo' is in an ok state
    Given check 'ping' for entity 'foo' is in scheduled maintenance for 4 hours
    And   check 'ping' for entity 'baz' is in an ok state
    When  a critical event is received for check 'ping' on entity 'foo'
    And   1 minute passes
    And   a critical event is received for check 'ping' on entity 'foo'
    Then  0 sms alerts should be queued for +61400000001
    When  5 minutes passes
    And   a critical event is received for check 'ping' on entity 'baz'
    And   1 minute passes
    And   a critical event is received for check 'ping' on entity 'baz'
    Then  1 sms alert of type problem and rollup none should be queued for +61400000001
    And   1 sms alerts should be queued for +61400000001
    When  4 hours passes
    And   a critical event is received for check 'ping' on entity 'foo'
    Then  2 sms alerts should be queued for +61400000001
    And   1 sms alert of type problem and rollup problem should be queued for +61400000001

  @time
  Scenario: Disabling a failing check suppresses rollup
    Given check 'ping' for entity 'foo' is in an ok state
    And   check 'ping' for entity 'baz' is in an ok state
    When  a critical event is received for check 'ping' on entity 'foo'
    And   1 minute passes
    And   a critical event is received for check 'ping' on entity 'foo'
    Then  1 sms alert should be queued for +61400000001
    Then  1 sms alerts of type problem and rollup none should be queued for +61400000001
    When  5 minutes passes
    And   a critical event is received for check 'ping' on entity 'baz'
    And   1 minute passes
    And   a critical event is received for check 'ping' on entity 'baz'
    Then  1 sms alert of type problem and rollup problem should be queued for +61400000001
    And   2 sms alerts should be queued for +61400000001
    When  check 'ping' on entity 'foo' is disabled
    And   30 minutes passes
    And   a critical event is received for check 'ping' on entity 'baz'
    Then  1 sms alert of rollup recovery should be queued for +61400000001

  @time
  Scenario: Enabling a failing check promotes rollup
    Given check 'ping' for entity 'foo' is in an ok state
    And   check 'ping' for entity 'baz' is in an ok state
    When  a critical event is received for check 'ping' on entity 'foo'
    And   1 minute passes
    And   a critical event is received for check 'ping' on entity 'foo'
    Then  1 sms alert should be queued for +61400000001
    Then  1 sms alert of type problem and rollup none should be queued for +61400000001
    When  check 'ping' for entity 'foo' is disabled
    And   5 minutes passes
    And   a critical event is received for check 'ping' on entity 'baz'
    And   1 minute passes
    And   a critical event is received for check 'ping' on entity 'baz'
    Then  2 sms alerts should be queued for +61400000001
    Then  1 sms alert of type problem and rollup none should be queued for +61400000001
    Then  1 sms alert of type problem and rollup recovery should be queued for +61400000001
    When  1 hour passes
    And   check 'ping' on entity 'foo' is enabled
    And   5 minutes passes
    And   a critical event is received for check 'ping' on entity 'foo'
    Then  3 sms alerts should be queued for +61400000001
    Then  1 sms alert of type problem and rollup none should be queued for +61400000001
    Then  1 sms alert of type problem and rollup recovery should be queued for +61400000001
    And   1 sms alert of type problem and rollup problem should be queued for +61400000001

  @time
  Scenario: Contact ceases to be a contact on an entity that they were being alerted for
    Given check 'ping' for entity 'foo' is in an ok state
    And   check 'ping' for entity 'baz' is in an ok state
    When  a critical event is received for check 'ping' on entity 'foo'
    And   1 minute passes
    And   a critical event is received for check 'ping' on entity 'foo'
    Then  1 sms alerts of type problem and rollup none should be queued for +61400000001
    When  5 minutes passes
    And   a critical event is received for check 'ping' on entity 'baz'
    And   1 minute passes
    And   a critical event is received for check 'ping' on entity 'baz'
    Then  1 sms alert of type problem and rollup problem should be queued for +61400000001
    And   1 sms alerts of type problem and rollup none should be queued for +61400000001
    And   2 sms alerts should be queued for +61400000001
    When  20 minute passes
    And   user 1 ceases to be a contact of entity 'foo'
    And   a critical event is received for check 'ping' on entity 'baz'
    Then  1 sms alert of rollup recovery should be queued for +61400000001

  @time
  Scenario: Test notification to not contribute to rollup
    Given check 'ping' for entity 'foo' is in an ok state
    And   check 'ping' for entity 'baz' is in an ok state
    When  a critical event is received for check 'ping' on entity 'foo'
    And   1 minute passes
    And   a critical event is received for check 'ping' on entity 'foo'
    Then  1 sms alert of type problem and rollup none should be queued for +61400000001
    And   1 sms alert should be queued for +61400000001
    When  1 minute passes
    And   a test event is received for check 'sausage' on entity 'foo'
    Then  1 sms alert of type problem and rollup none should be queued for +61400000001
    And   1 sms alert of type test and rollup none should be queued for +61400000001
    And   2 sms alerts should be queued for +61400000001
    When  20 minutes passes
    And   a critical event is received for check 'ping' on entity 'foo'
    Then  2 sms alerts of type problem and rollup none should be queued for +61400000001
    And   3 sms alerts should be queued for +61400000001

  @time
  Scenario: Multiple notifications should not occur when in rollup
    Given check 'ping' for entity 'foo' is in an ok state
    And   check 'ping' for entity 'baz' is in an ok state
    When  a critical event is received for check 'ping' on entity 'foo' with details 'event 1: no notif, delay'
    And   a critical event is received for check 'ping' on entity 'baz' with details 'event 2: no notif, delay'
    And   1 minute passes
    And   a critical event is received for check 'ping' on entity 'foo' with details 'event 3: alert: email (rollup), sms'
    And   a critical event is received for check 'ping' on entity 'baz' with details 'event 4: alert: email (none), sms (rollup)'
    And   1 minute passes
    And   a critical event is received for check 'ping' on entity 'foo' with details 'event 5: alert: email (none - drop alerts), sms (none - drop alerts)'
    Then  1 email alert of type problem and rollup problem should be queued for malak@example.com
    And   19 minutes passes
    # We have two alerting checks, so both notifications are in rollup mode
    And   a critical event is received for check 'ping' on entity 'baz' with details 'event 6: alert: email (rollup), sms (rollup)'
    Then  2 email alerts of type problem and rollup problem should be queued for malak@example.com
    And   1 minute passes
    And   a critical event is received for check 'ping' on entity 'baz' with details 'event 7: alert: email (none), sms (none)'
    Then  2 email alerts of type problem and rollup problem should be queued for malak@example.com

  @time
  Scenario: Multiple notifications should not occur when in rollup (v2)
    Given check 'ping' for entity 'foo' is in an ok state
    And   check 'ping' for entity 'baz' is in an ok state
    And   check 'ping' for entity 'zoo' is in an ok state

    # No notifications due to initial_failure_delay
    When  a critical event is received for check 'ping' on entity 'foo' with details 'event 1: no notif, delay'
    And   a critical event is received for check 'ping' on entity 'baz' with details 'event 2: no notif, delay'
    And   a critical event is received for check 'ping' on entity 'zoo' with details 'event 3: no notif, delay'
    And   1 minute passes

    # One email notification, move to rollup
    And   a critical event is received for check 'ping' on entity 'foo' with details 'event 4: alert: email (rollup)'
    Then  1 email alert of type problem and rollup problem should be queued for malak@example.com

    # No more email notifications, due to rollup
    And   a critical event is received for check 'ping' on entity 'baz' with details 'event 5: alert: email (none)'
    And   a critical event is received for check 'ping' on entity 'zoo' with details 'event 6: alert: email (none)'
    Then  1 email alert of type problem and rollup problem should be queued for malak@example.com

    And 20 minutes passes
    # The rollup expired

    # We send the recovery, but we are still in rollup mode
    And   an ok event is received for check 'ping' on entity 'foo' with details 'event 7: alert: email (rollup)'
    Then  1 email alert of type problem and rollup problem should be queued for malak@example.com
    Then  1 email alert of type recovery and rollup problem should be queued for malak@example.com

    # Another recovery, email should not be sent, we are still in rollup mode, and we have just sent one
    And   an ok event is received for check 'ping' on entity 'baz' with details 'event 8'
    Then  1 email alert of type recovery and rollup problem should be queued for malak@example.com
    Then  0 email alert of type recovery and rollup recovery should be queued for malak@example.com

    # Another recovery, email should not be sent, we are still in rollup mode, and we have just sent one
    And   an ok event is received for check 'ping' on entity 'zoo' with details 'event 9'
    Then  1 email alert of type recovery and rollup problem should be queued for malak@example.com
    Then  1 email alert of type recovery and rollup recovery should be queued for malak@example.com