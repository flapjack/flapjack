@rollup @notification_rules @resque @processor @notifier @events
Feature: Rollup on a per contact, per media basis

  Background:
    Given the following contacts exist:
      | id  | name            | timezone            |
      | c1  | Malak Al-Musawi | Asia/Baghdad        |

    And the following media exist:
      | id  | contact_id | type  | address           | initial_failure_interval | repeat_failure_interval | rollup_threshold |
      | m1e | c1         | email | malak@example.com | 15                       | 15                      | 1                |
      | m1s | c1         | sms   | +61400000001      | 60                       | 15                      | 2                |

    And the following checks exist:
      | id  | name     | tags     |
      | 1   | foo:ping | foo,ping |
      | 2   | baz:ping | baz,ping |

    And the following rules exist:
      | id | contact_id | tags     |
      | r1 | c1         | foo,ping |
      | r2 | c1         | baz,ping |

    And the following routes exist:
      | id  | rule_id | state    | time_restrictions | drop | media_ids |
      | o1a | r1      | critical |                   |      | m1e,m1s   |
      | o1b | r1      | warning  |                   |      | m1e       |
      | o2a | r2      | critical |                   |      | m1e,m1s   |
      | o2b | r2      | warning  |                   |      | m1e       |

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
    When  a critical event is received for check 'ping' on entity 'foo'
    Then  no sms alerts should be queued for +61400000001
    When  1 minute passes
    And   a critical event is received for check 'ping' on entity 'foo'
    Then  1 sms alert of type problem and rollup none should be queued for +61400000001
    When  5 minutes passes
    And   a critical event is received for check 'ping' on entity 'baz'
    And   1 minute passes
    And   a critical event is received for check 'ping' on entity 'baz'
    Then  1 sms alert of type problem and rollup none should be queued for +61400000001
    And   1 sms alert of type problem and rollup problem should be queued for +61400000001
    When  1 minute passes
    And   an ok event is received for check 'ping' on entity 'foo'
    Then  no sms alerts of type recovery and rollup none should be queued for +61400000001
    And   1 sms alert of type recovery and rollup recovery should be queued for +61400000001
    And   3 sms alerts should be queued for +61400000001
    When  1 minute passes
    And   an ok event is received for check 'ping' on entity 'baz'
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
    When  1 minute passes
    And   a critical event is received for check 'ping' on entity 'foo'
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
  Scenario: Contact removes a rule matching on a check
    Given PENDING: more data model refactoring is needed
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
    And   user with id 'c1' removes rule with id 'r1'
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
    When  1 minute passes
    And   a test event is received for check 'ping' on entity 'foo'
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
    When  a critical event is received for check 'ping' on entity 'foo'
    And   a critical event is received for check 'ping' on entity 'baz'
    And   1 minute passes
    And   a critical event is received for check 'ping' on entity 'foo'
    And   a critical event is received for check 'ping' on entity 'baz'
    And   1 minute passes
    And   a critical event is received for check 'ping' on entity 'foo'
    Then  1 email alert of type problem and rollup problem should be queued for malak@example.com
    And   19 minutes passes
    And   a critical event is received for check 'ping' on entity 'baz'
    Then  2 email alerts of type problem and rollup problem should be queued for malak@example.com
    And   1 minute passes
    And   a critical event is received for check 'ping' on entity 'baz'
    Then  2 email alerts of type problem and rollup problem should be queued for malak@example.com
