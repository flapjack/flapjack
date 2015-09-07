@rollup @notification_rules @processor @notifier @events
Feature: Multiple acknowledgements after scheduled maintenance

  Background:
    Given the following contacts exist:
      | id                                   | name            | timezone     |
      | 7f96a216-76aa-45fc-a88e-7431cd6d7aac | Malak Al-Musawi | Asia/Baghdad |

    And the following media exist:
      | id                                   | contact_id                           | transport | address           | interval | rollup_threshold |
      | 28032dbf-388d-4f52-91b2-dc5e5be2becc | 7f96a216-76aa-45fc-a88e-7431cd6d7aac | email     | malak@example.com | 15       | 3                |
      | 73e2803f-948e-467a-a707-37b9f53ee21a | 7f96a216-76aa-45fc-a88e-7431cd6d7aac | sms       | +61400000001      | 15       | 3                |

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
  Scenario: Multiple acks after sched maint ends
    Given the check is check 'ping' on entity 'foo'
    And   the check is in an ok state
    And   the check is in scheduled maintenance for 1 hour
    When  1 minute passes
    And   a critical event is received
    Then  no email alerts should be queued for malak@example.com
    When  60 minutes passes
    And   a critical event is received
    Then  1 email alert of type problem should be queued for malak@example.com
    When  1 minute passes
    And   an acknowledgement event is received
    Then  1 email alert of type acknowledgement should be queued for malak@example.com
    When  1 minute passes
    And   an acknowledgement event is received
    Then  1 email alert of type acknowledgement should be queued for malak@example.com