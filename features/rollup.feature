@rollup @notification_rules @resque @processor @notifier @events
Feature: Rollup on a per contact, per media basis

  Background:
    Given the following contacts exist:
      | id                                   | name            | timezone     |
      | 7f96a216-76aa-45fc-a88e-7431cd6d7aac | Malak Al-Musawi | Asia/Baghdad |

    And the following media exist:
      | id                                   | contact_id                           | transport | address           | interval | rollup_threshold |
      | 28032dbf-388d-4f52-91b2-dc5e5be2becc | 7f96a216-76aa-45fc-a88e-7431cd6d7aac | email     | malak@example.com | 15       | 1                |
      | 73e2803f-948e-467a-a707-37b9f53ee21a | 7f96a216-76aa-45fc-a88e-7431cd6d7aac | sms       | +61400000001      | 15       | 2                |

    And the following checks exist:
      | id                                   | name     | tags     |
      | 56c13ce2-f246-4bc6-adfa-2206789c3ced | foo:ping | foo,ping |
      | d1a39575-0480-4f65-a7f7-64c90db93731 | baz:ping | baz,ping |

    And the following rules exist:
      | id                                   | contact_id                           | blackhole | strategy | tags     | condition | time_restriction | media_ids                                                                 |
      | b0c8deb9-b8c8-4fdd-acc4-72493852ca15 | 7f96a216-76aa-45fc-a88e-7431cd6d7aac | false     | all_tags | foo,ping | critical  |                   | 28032dbf-388d-4f52-91b2-dc5e5be2becc,73e2803f-948e-467a-a707-37b9f53ee21a |
      | b18e9f48-59e7-4c25-b94c-d4ebd4a6559a | 7f96a216-76aa-45fc-a88e-7431cd6d7aac | false     | all_tags | foo,ping | warning   |                   | 28032dbf-388d-4f52-91b2-dc5e5be2becc                                      |
      | 2df6bbc4-d6a4-4f23-b6e5-5c4a07c6e686 | 7f96a216-76aa-45fc-a88e-7431cd6d7aac | false     | all_tags | baz,ping | critical  |                   | 28032dbf-388d-4f52-91b2-dc5e5be2becc,73e2803f-948e-467a-a707-37b9f53ee21a |
      | f163bf33-b53e-4138-ab27-1dd89f2d6fdd | 7f96a216-76aa-45fc-a88e-7431cd6d7aac | false     | all_tags | baz,ping | warning   |                   | 28032dbf-388d-4f52-91b2-dc5e5be2becc                                      |

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
    Then  1 sms alerts should be queued for +61400000001
    Then  1 sms alert of type problem and rollup none should be queued for +61400000001
    When  1 hour passes
    And   check 'ping' on entity 'foo' is enabled
    And   5 minutes passes
    And   a critical event is received for check 'ping' on entity 'foo'
    Then  2 sms alerts should be queued for +61400000001
    Then  1 sms alert of type problem and rollup none should be queued for +61400000001
    And   1 sms alert of type problem and rollup problem should be queued for +61400000001

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
    And   the rule with id 'b0c8deb9-b8c8-4fdd-acc4-72493852ca15' is removed
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
