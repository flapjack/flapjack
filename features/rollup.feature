@rollup @notification_rules @resque @processor @notifier
Feature: Rollup on a per contact, per media basis

  Background:
    Given the following users exist:
      | id  | first_name | last_name | email             | sms          | timezone         |
      | 1   | Malak      | Al-Musawi | malak@example.com | +61400000001 | Asia/Baghdad     |

    And the following entities exist:
      | id  | name           | contacts |
      | 1   | foo            | 1        |

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
    Then  1 email alert of type rollup should be queued for malak@example.com
    When  1 minute passes
    And   an ok event is received
    Then  1 email alert of type rollup_recovery should be queued for malak@example.com

  @time
  Scenario: Transition to rollup when threshold is met
    And   check 'ping' for entity 'foo' is in an ok state
    When  a critical event is received for check 'ping' on entity 'foo'
    Then  no sms alerts should be queued for malak@example.com
    When  1 minute passes
    And   a critical event is received for check 'ping' on entity 'foo'
    Then  1 sms alert of type problem should be queued for +61400000001
    When  5 minutes passes
    And   a critical event is received for check 'ping' on entity 'baz'
    And   1 minute passes
    And   a critical event is received for check 'ping' on entity 'baz'
    Then  1 sms alert of type problem should be queued for +61400000001
    And   1 sms alert of type rollup_problem should be queued for +61400000001
    When  1 minute passes
    And   an ok event is received for check 'ping' on entity 'foo'
    Then  no sms alerts of type recovery should be queued for +61400000001
    And   1 sms alert of type rollup_recovery should be queued for +61400000001
    And   3 sms alerts should be queued for +61400000001
    When  1 minute passes
    And   an ok event is received for check 'ping' on entity 'baz'
    Then  1 sms alert of type recovery should be queued for +61400000001
    And   1 sms alert of type rollup_recovery should be queued for +61400000001
    And   4 sms alerts should be queued for +61400000001
