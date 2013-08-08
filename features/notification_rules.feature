@notification_rules @processor @notifier
Feature: Notification rules on a per contact basis

  Background:
    Given the following users exist:
      | id  | first_name | last_name | email             | sms          | timezone         |
      | 1   | Malak      | Al-Musawi | malak@example.com | +61400000001 | Asia/Baghdad     |
      | 2   | Imani      | Farooq    | imani@example.com | +61400000002 | Europe/Moscow    |
      | 3   | Vera       | Дурейко   | vera@example.com  | +61400000003 | Europe/Paris     |
      | 4   | Lucia      | Moretti   | lucia@example.com | +61400000004 | Europe/Rome      |

    And the following entities exist:
      | id  | name           | contacts |
      | 1   | foo            | 1        |
      | 2   | bar            | 1,2,3    |
      | 3   | baz            | 1,3      |
      | 4   | buf            | 1,2,3    |
      | 5   | foo-app-01.xyz | 4        |

    And user 1 has the following notification intervals:
      | email | sms |
      | 15    | 60  |

    And user 2 has the following notification intervals:
      | email | sms |
      | 15    | 60  |

    And user 3 has the following notification intervals:
      | email | sms |
      | 15    | 60  |

    And user 4 has the following notification intervals:
      | email | sms |
      | 15    | 60  |

    And user 1 has the following notification rules:
      | entities | tags | warning_media | critical_media   | warning_blackhole | critical_blackhole | time_restrictions |
      |          |      | email         | sms,email        | true              | true               |                   |
      | foo      |      | email         | sms,email        |                   |                    | 8-18 weekdays     |
      | bar      |      |               | sms,email        | true              |                    |                   |
      | baz      |      | email         | sms,email        |                   |                    |                   |

    And user 2 has the following notification rules:
      | entities | tags | warning_media | critical_media   | warning_blackhole | critical_blackhole | time_restrictions |
      |          |      | email         | email            |                   |                    |                   |
      |          |      | sms           | sms              |                   |                    |                   |
      | bar      |      | email         | email,sms        |                   |                    |                   |

    And user 3 has the following notification rules:
      | entities | tags            | warning_media | critical_media   | warning_blackhole | critical_blackhole | time_restrictions |
      |          |                 | email         | email            |                   |                    |                   |
      | baz      |                 | sms           | sms              |                   |                    |                   |
      | buf      |                 | email         | email            |                   |                    |                   |
      | buf      |                 | sms           | sms              |                   |                    |                   |

    And user 4 has the following notification rules:
      | entities | tags            | warning_media | critical_media   | warning_blackhole | critical_blackhole | time_restrictions |
      |          |                 |               |                  |                   |                    |                   |
      |          | xyz, disk, util | sms           | sms              |                   |                    |                   |
      |          | xyz, ping       | sms,email     | sms,email        |                   |                    | 8-18 weekdays     |

  @time_restrictions @time
  Scenario: Alerts only during specified time restrictions
    Given the timezone is Asia/Baghdad
    And   the time is February 1 2013 6:59
    And   the check is check 'ping' on entity 'foo'
    And   the check is in an ok state
    And   a critical event is received
    Then  no email alerts should be queued for malak@example.com
    And   the time is February 1 2013 7:01
    And   a critical event is received
    Then  no email alerts should be queued for malak@example.com
    And   the time is February 1 2013 8:01
    And   a critical event is received
    Then  1 email alert should be queued for malak@example.com
    When  the time is February 1 2013 12:00
    Then  all alert dropping keys for user 1 should have expired
    When  a critical event is received
    Then  2 email alerts should be queued for malak@example.com
    When  the time is February 1 2013 17:59
    Then  all alert dropping keys for user 1 should have expired
    When  a critical event is received
    Then  3 email alerts should be queued for malak@example.com
    When  the time is February 1 2013 18:01
    Then  all alert dropping keys for user 1 should have expired
    When  a critical event is received
    Then  3 email alerts should be queued for malak@example.com

  Scenario: time restrictions continue to work as expected when a contact changes timezone

  @severity @time
  Scenario: Don't alert when media,severity does not match any matching rule's severity's media
    Given the check is check 'ping' on entity 'bar'
    And   the check is in an ok state
    When  a warning event is received
    And   60 minutes passes
    And   a warning event is received
    Then  no email alerts should be queued for malak@example.com

  @severity @time
  Scenario: Recoveries are not affected by notification rules
    Given the check is check 'ping' on entity 'baz'
    And   the check is in an ok state
    When  a critical event is received
    And   5 minutes passes
    And   a critical event is received
    Then  1 email alert should be queued for malak@example.com
    When  1 minute passes
    And   an ok event is received
    Then  2 email alerts should be queued for malak@example.com

  @severity @time
  Scenario: Alerts are sent to media of highest severity reached since last ok
    Given the check is check 'ping' on entity 'baz'
    And   the check is in an ok state
    When  a warning event is received
    And   1 minute passes
    And   a warning event is received
    Then  1 email alert should be queued for malak@example.com
    And   0 sms alerts should be queued for +61400000001
    When  70 minutes passes
    And   a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  2 email alerts should be queued for malak@example.com
    And   1 sms alert should be queued for +61400000001
    When  70 minutes passes
    And   a warning event is received
    And   1 minute passes
    And   a warning event is received
    Then  3 email alerts should be queued for malak@example.com
    And   2 sms alerts should be queued for +61400000001
    When  70 minutes passes
    And   an ok event is received
    Then  4 email alerts should be queued for malak@example.com
    And   3 sms alerts should be queued for +61400000001

  @severity @time
  Scenario: Alerts only when media,severity matches any matching rule's severity's media with ok->warning->critical->ok
    Given the check is check 'ping' on entity 'bar'
    And   the check is in an ok state
    When  a warning event is received
    And   1 minute passes
    And   a warning event is received
    Then  no email alerts should be queued for malak@example.com
    When  a critical event is received
    And   5 minutes passes
    And   a critical event is received
    Then  1 email alert should be queued for malak@example.com
    When  1 minute passes
    And   an ok event is received
    Then  2 email alert should be queued for malak@example.com

  @blackhole
  Scenario: Drop alerts matching a blackhole rule

  @intervals @time
  Scenario: Alerts according to custom interval
    Given the check is check 'ping' on entity 'bar'
    And   the check is in an ok state
    When  a critical event is received
    Then  no email alerts should be queued for malak@example.com
    When  1 minute passes
    And   a critical event is received
    Then  1 email alert should be queued for malak@example.com
    When  10 minutes passes
    And   a critical event is received
    Then  1 email alert should be queued for malak@example.com
    When  5 minutes passes
    And   a critical event is received
    Then  2 email alerts should be queued for malak@example.com

  @intervals @time
  Scenario: Alerts according to custom interval with unknown
    Given the check is check 'ping' on entity 'bar'
    And   the check is in an ok state
    When  an unknown event is received
    Then  no email alerts should be queued for malak@example.com
    When  1 minute passes
    And   an unknown event is received
    Then  1 email alert should be queued for malak@example.com
    When  10 minutes passes
    And   an unknown event is received
    Then  1 email alert should be queued for malak@example.com
    When  5 minutes passes
    And   an unknown event is received
    Then  2 email alerts should be queued for malak@example.com

  @intervals @time
  Scenario: Problem directly after Recovery should alert despite notification intervals
    Given the check is check 'ping' on entity 'baz'
    And   the check is in an ok state
    When  a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  1 email alert should be queued for malak@example.com
    And   1 sms alert should be queued for +61400000001
    When  an ok event is received
    Then  2 email alerts should be queued for malak@example.com
    And   2 sms alerts should be queued for +61400000001
    When  1 minute passes
    And   a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  3 email alerts should be queued for malak@example.com
    And   3 sms alerts should be queued for +61400000001

  @intervals @time
  Scenario: Problem directly after Recovery should alert despite notification intervals with unknown
    Given the check is check 'ping' on entity 'baz'
    And   the check is in an ok state
    When  an unknown event is received
    And   1 minute passes
    And   an unknown event is received
    Then  1 email alert should be queued for malak@example.com
    And   1 sms alert should be queued for +61400000001
    When  an ok event is received
    Then  2 email alert should be queued for malak@example.com
    And   2 sms alerts should be queued for +61400000001
    When  1 minute passes
    And   an unknown event is received
    And   1 minute passes
    And   an unknown event is received
    Then  3 email alerts should be queued for malak@example.com
    And   3 sms alerts should be queued for +61400000001

  @time
  Scenario: Contact with only entity specific rules should not be notified for other entities they are a contact for
    Given the check is check 'ping' on entity 'buf'
    And   the check is in an ok state
    When  a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  no email alerts should be queued for malak@example.com

  @time
  Scenario: Contact with entity specific rules and general rules should be notified for other entities they are a contact for
    Given the check is check 'ping' on entity 'buf'
    And   the check is in an ok state
    When  a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  1 email alert should be queued for imani@example.com

  @time
  Scenario: Mutiple rules for an entity should be additive
    Given the check is check 'ping' on entity 'buf'
    And   the check is in an ok state
    When  a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  1 email alert should be queued for vera@example.com
    Then  1 sms alert should be queued for +61400000003

  @time
  Scenario: Multiple general rules should be additive
    Given the check is check 'ping' on entity 'buf'
    And   the check is in an ok state
    When  a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  1 email alert should be queued for imani@example.com
    Then  1 sms alert should be queued for +61400000002

  @time
  Scenario: An entity specific rule should override general rules
    Given the check is check 'ping' on entity 'baz'
    And   the check is in an ok state
    When  a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  0 email alerts should be queued for vera@example.com
    Then  1 sms alert should be queued for +61400000003

  @time
  Scenario: Test notifications behave like a critical notification
    Given the check is check 'ping' on entity 'foo'
    And   the check is in an ok state
    When  a test event is received
    Then  1 email alert should be queued for malak@example.com
    And   1 sms alert should be queued for +61400000001
  @time
  Scenario: Critical straight after test
    Given the check is check 'ping' on entity 'baz'
    And   the check is in an ok state
    When  a test event is received
    Then  1 email alert should be queued for malak@example.com
    And   1 sms alert should be queued for +61400000001
    When  10 seconds passes
    And   a critical event is received
    Then  1 email alert should be queued for malak@example.com
    And   1 sms alert should be queued for +61400000001
    When  40 seconds passes
    And   a critical event is received
    Then  2 email alert should be queued for malak@example.com
    And   2 sms alert should be queued for +61400000001

  Scenario: Unknown event during unscheduled maintenance
    Given the check is check 'ping' on entity 'foo'
    And   the check is in an ok state
    When  an unknown event is received
    And   1 minute passes
    And   an unknown event is received
    Then  1 email alert should be queued for malak@example.com
    And   1 sms alert should be queued for +61400000001
    When  6 minutes passes
    And   an acknowledgement event is received
    Then  2 email alerts should be queued for malak@example.com
    And   2 sms alerts should be queued for +61400000001
    When  6 minutes passes
    And   an unknown event is received
    Then  2 email alerts should be queued for malak@example.com
    And   2 sms alerts should be queued for +61400000001
    When  1 minute passes
    And   an unknown event is received
    Then  2 email alerts should be queued for malak@example.com
    And   2 sms alerts should be queued for +61400000001

  @time
  Scenario: A blackhole rule on an entity should override another matching entity specific rule

  @time
  Scenario: A blackhole rule on an entity should override another matching general rule

  @time
  Scenario: Notify when tags in a rule match the event's tags
    Given the check is check 'Disk / Util' on entity 'foo-app-01.xyz'
    And   the check is in an ok state
    When  a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  1 sms alert should be queued for +61400000004

  @time
  Scenario: Don't notify when tags in a rule don't match the event's tags
    Given the check is check 'Memory Util' on entity 'foo-app-01.xyz'
    And   the check is in an ok state
    When  a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  no sms alerts should be queued for +61400000004

  @time
  Scenario: Only notify during specified time periods in tag matched rules
    Given the timezone is Europe/Rome
    And   the time is February 1 2013 6:59
    And   the check is check 'ping' on entity 'foo-app-01.xyz'
    And   the check is in an ok state
    And   a critical event is received
    Then  no sms alerts should be queued for +61400000004
    And   the time is February 1 2013 7:01
    And   a critical event is received
    Then  no sms alerts should be queued for +61400000004
    And   the time is February 1 2013 8:01
    And   a critical event is received
    Then  1 sms alert should be queued for +61400000004
    When  the time is February 1 2013 12:00
    Then  all alert dropping keys for user 1 should have expired
    When  a critical event is received
    Then  2 sms alerts should be queued for +61400000004
    When  the time is February 1 2013 17:59
    Then  all alert dropping keys for user 1 should have expired
    When  a critical event is received
    Then  3 sms alerts should be queued for +61400000004
    When  the time is February 1 2013 18:01
    Then  all alert dropping keys for user 1 should have expired
    When  a critical event is received
    Then  3 sms alerts should be queued for +61400000004


