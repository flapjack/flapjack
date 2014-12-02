@rollup @notification_rules @resque @processor @notifier @events
Feature: Multiple acknowledgements after scheduled maintenance

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
      | 3     | 3   |

    And user 1 has the following notification rules:
      | entities | unknown_media | warning_media | critical_media   |
      |          |               | email         | sms,email        |

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
    And   the check should appear in unacknowledged_failing
    When  1 minute passes
    And   an acknowledgement event is received
    Then  1 email alert of type acknowledgement should be queued for malak@example.com
    And   the check should not appear in unacknowledged_failing
    When  1 minute passes
    And   an acknowledgement event is received
    Then  2 email alert of type acknowledgement should be queued for malak@example.com

