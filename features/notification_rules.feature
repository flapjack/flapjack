@notification_rules @processor @notifier
Feature: Notification rules on a per contact basis

  Background:
    Given the following contacts exist:
      | id  | name            | timezone            |
      | c1  | Malak Al-Musawi | Asia/Baghdad        |
      | c2  | Imani Farooq    | Europe/Moscow       |
      | c3  | Vera Дурейко    | Europe/Paris        |
      | c4  | Lucia Moretti   | Europe/Rome         |
      | c5  | Wang Fang Wong  | Asia/Shanghai       |

    And the following media exist:
      | id  | contact_id | type  | address           | interval | rollup_threshold |
      | m1e | c1         | email | malak@example.com | 15       | 5                |
      | m1s | c1         | sms   | +61400000001      | 60       | 5                |
      | m2e | c2         | email | imani@example.com | 15       | 5                |
      | m2s | c2         | sms   | +61400000002      | 60       | 5                |
      | m3e | c3         | email | vera@example.com  | 15       | 5                |
      | m3s | c3         | sms   | +61400000003      | 60       | 5                |
      | m4e | c4         | email | lucia@example.com | 15       | 5                |
      | m4s | c4         | sms   | +61400000004      | 60       | 5                |
      | m5e | c5         | email | fang@example.com  | 15       | 5                |
      | m5s | c5         | sms   | +61400000005      | 60       | 5                |

    And the following checks exist:
      | id  | name                       | tags      |
      | 1   | foo:ping                   | foo,ping  |
      | 2   | bar:ping                   | bar,ping  |
      | 3   | baz:ping                   | baz,ping  |
      | 4   | buf:ping                   | buf,ping  |

    And the following rules exist:
      | id | contact_id | tags     |
      | r1 | c1         | foo,ping |
      | r2 | c2         | bar,ping |
      | r3 | c3         | foo,ping |
      | r4 | c4         | baz,ping |
      | r5 | c1         | buf,ping |
      | r6 | c1         | buf,ping |
      | r7 | c5         |          |

    And the following routes exist:
      | id  | rule_id | state    | time_restrictions | drop | media_ids |
      | o1  | r1      | critical | 8-18 weekdays     |      | m1e       |
      | o2a | r2      | critical |                   |      | m2e       |
      | o2b | r2      | unknown  |                   |      | m2e       |
      | o3a | r3      | critical |                   |      | m3e       |
      | o3b | r3      |          |                   |      | m3s       |
      | o4a | r4      | critical | 8-18 weekdays     |      | m4e,m4s   |
      | o4b | r4      | warning  | 8-18 weekdays     |      | m4e       |
      | o5  | r5      | critical |                   |      | m1e       |
      | o6  | r6      |          |                   | y    | m1e       |
      | o7a | r7      |          |                   |      | m5e       |
      | o7b | r7      |          |                   |      | m5s       |

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
    Then  all alert dropping keys for user c1 should have expired
    When  a critical event is received
    Then  2 email alerts should be queued for malak@example.com
    When  the time is February 1 2013 17:59
    Then  all alert dropping keys for user c1 should have expired
    When  a critical event is received
    Then  3 email alerts should be queued for malak@example.com
    When  the time is February 1 2013 18:01
    When  a critical event is received
    Then  3 email alerts should be queued for malak@example.com

  # Scenario: time restrictions continue to work as expected when a contact changes timezone

  @severity @time
  Scenario: Don't alert when severity does not match any matching routes's severity
    Given the check is check 'ping' on entity 'bar'
    And   the check is in an ok state
    When  a warning event is received
    And   60 minutes passes
    And   a warning event is received
    Then  no email alerts should be queued for imani@example.com

  @severity @time
  Scenario: Recoveries are not affected by intervals
    Given the check is check 'ping' on entity 'foo'
    And   the check is in an ok state
    When  a critical event is received
    And   5 minutes passes
    And   a critical event is received
    Then  1 email alert should be queued for vera@example.com
    When  1 minute passes
    And   an ok event is received
    Then  2 email alerts should be queued for vera@example.com

  @severity @time
  Scenario: Alerts are sent to media of highest severity reached since last ok
    Given the timezone is Europe/Rome
    And   the time is February 1 2013 8:01
    And   the check is check 'ping' on entity 'baz'
    And   the check is in an ok state
    When  a warning event is received
    And   1 minute passes
    And   a warning event is received
    Then  1 email alert should be queued for lucia@example.com
    And   0 sms alerts should be queued for +61400000004
    When  70 minutes passes
    And   a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  2 email alerts should be queued for lucia@example.com
    And   1 sms alert should be queued for +61400000004
    When  70 minutes passes
    And   a warning event is received
    And   1 minute passes
    And   a warning event is received
    Then  3 email alerts should be queued for lucia@example.com
    And   2 sms alerts should be queued for +61400000004
    When  70 minutes passes
    And   an ok event is received
    Then  4 email alerts should be queued for lucia@example.com
    And   3 sms alerts should be queued for +61400000004

  @severity @time
  Scenario: Alerts only when media,severity matches any matching rule's severity's media with ok->warning->critical->ok
    Given the check is check 'ping' on entity 'bar'
    And   the check is in an ok state
    When  a warning event is received
    And   1 minute passes
    And   a warning event is received
    Then  no email alerts should be queued for imani@example.com
    When  a critical event is received
    And   5 minutes passes
    And   a critical event is received
    Then  1 email alert should be queued for imani@example.com
    When  1 minute passes
    And   an ok event is received
    Then  2 email alert should be queued for imani@example.com

  @blackhole @time
  Scenario: Drop alerts matching a blackhole route
    Given the check is check 'ping' on entity 'buf'
    And   the check is in an ok state
    When  a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  0 email alerts should be queued for malak@example.com

  @intervals @time
  Scenario: Alerts according to custom interval
    Given the check is check 'ping' on entity 'bar'
    And   the check is in an ok state
    When  a critical event is received
    Then  no email alerts should be queued for imani@example.com
    When  1 minute passes
    And   a critical event is received
    Then  1 email alert should be queued for imani@example.com
    When  10 minutes passes
    And   a critical event is received
    Then  1 email alert should be queued for imani@example.com
    When  6 minutes passes
    And   a critical event is received
    Then  2 email alerts should be queued for imani@example.com

  @intervals @time
  Scenario: Alerts according to custom interval with unknown
    Given the check is check 'ping' on entity 'bar'
    And   the check is in an ok state
    When  an unknown event is received
    Then  no email alerts should be queued for imani@example.com
    When  1 minute passes
    And   an unknown event is received
    Then  1 email alert should be queued for imani@example.com
    When  10 minutes passes
    And   an unknown event is received
    Then  1 email alert should be queued for imani@example.com
    When  6 minutes passes
    And   an unknown event is received
    Then  2 email alerts should be queued for imani@example.com

  @intervals @time
  Scenario: Problem directly after recovery should alert despite notification intervals
    Given the timezone is Europe/Rome
    And   the time is February 1 2013 8:01
    And   the check is check 'ping' on entity 'baz'
    And   the check is in an ok state
    When  a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  1 email alert should be queued for lucia@example.com
    And   1 sms alert should be queued for +61400000004
    When  an ok event is received
    Then  2 email alerts should be queued for lucia@example.com
    And   2 sms alerts should be queued for +61400000004
    When  1 minute passes
    And   a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  3 email alerts should be queued for lucia@example.com
    And   3 sms alerts should be queued for +61400000004

  @intervals @time
  Scenario: Problem directly after Recovery should alert despite notification intervals with unknown
    Given the check is check 'ping' on entity 'bar'
    And   the check is in an ok state
    When  an unknown event is received
    And   1 minute passes
    And   an unknown event is received
    Then  1 email alert should be queued for imani@example.com
    When  an ok event is received
    Then  2 email alert should be queued for imani@example.com
    When  1 minute passes
    And   an unknown event is received
    And   1 minute passes
    And   an unknown event is received
    Then  3 email alerts should be queued for imani@example.com

  @time
  Scenario: Contact without a general rule is not notified for non-matching checks
    Given the check is check 'ping' on entity 'baz'
    And   the check is in an ok state
    When  a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  no email alerts should be queued for malak@example.com

  @time
  Scenario: Contact with a general rule should be notified for all events
    Given the check is check 'ping' on entity 'bar'
    And   the check is in an ok state
    When  a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  1 email alert should be queued for fang@example.com

  @time
  Scenario: Mutiple matching rules should be additive
    Given the check is check 'ping' on entity 'foo'
    And   the check is in an ok state
    When  a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  1 email alert should be queued for vera@example.com
    Then  1 sms alert should be queued for +61400000003

  @time
  Scenario: Multiple general rules should be additive
    Given the check is check 'ping' on entity 'bar'
    And   the check is in an ok state
    When  a critical event is received
    And   1 minute passes
    And   a critical event is received
    Then  1 email alert should be queued for fang@example.com
    Then  1 sms alert should be queued for +61400000005

  @time
  Scenario: Test notifications behave like a critical notification
    Given the check is check 'ping' on entity 'bar'
    And   the check is in an ok state
    When  a test event is received
    Then  1 email alert should be queued for imani@example.com

  @time
  Scenario: Critical straight after test
    Given the check is check 'ping' on entity 'bar'
    And   the check is in an ok state
    When  a test event is received
    Then  1 email alert should be queued for imani@example.com
    When  10 seconds passes
    And   a critical event is received
    Then  1 email alert should be queued for imani@example.com
    When  40 seconds passes
    And   a critical event is received
    Then  2 email alert should be queued for imani@example.com

  @time
  Scenario: Unknown event during unscheduled maintenance
    Given the check is check 'ping' on entity 'bar'
    And   the check is in an ok state
    When  an unknown event is received
    And   1 minute passes
    And   an unknown event is received
    Then  1 email alert should be queued for imani@example.com
    When  6 minutes passes
    And   an acknowledgement event is received
    Then  2 email alerts should be queued for imani@example.com
    When  6 minutes passes
    And   an unknown event is received
    Then  2 email alerts should be queued for imani@example.com
    When  1 minute passes
    And   an unknown event is received
    Then  2 email alerts should be queued for imani@example.com

  Scenario: Unknown events alert only specified media
    Given the check is check 'ping' on entity 'bar'
    And   the check is in an ok state
    When  an unknown event is received
    And   1 minute passes
    And   an unknown event is received
    Then  0 sms alerts should be queued for +61400000002

  @time
  Scenario: Only notify during specified time periods
    Given the timezone is Europe/Rome
    And   the time is February 1 2013 6:59
    And   the check is check 'ping' on entity 'baz'
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
    Then  all alert dropping keys for user c1 should have expired
    When  a critical event is received
    Then  2 sms alerts should be queued for +61400000004
    When  the time is February 1 2013 17:59
    Then  all alert dropping keys for user c1 should have expired
    When  a critical event is received
    Then  3 sms alerts should be queued for +61400000004
    When  the time is February 1 2013 18:01
    Then  all alert dropping keys for user c1 should have expired
    When  a critical event is received
    Then  3 sms alerts should be queued for +61400000004

  # tests that notifications are sent as acknowledgement clears the notification intervals
  @time
  Scenario: an second acknowledgement is created after the first is deleted (gh-308)
    Given the check is check 'ping' on entity 'bar'
    And the check is in an ok state
    When a critical event is received
    And 1 minute passes
    And a critical event is received
    Then 1 email alert should be queued for imani@example.com
    When 1 minute passes
    And an acknowledgement event is received
    Then unscheduled maintenance should be generated
    And 2 email alerts should be queued for imani@example.com
    When 1 minute passes
    And the unscheduled maintenance is ended
    And 1 minute passes
    And a critical event is received
    Then 3 email alerts should be queued for imani@example.com
    When 1 minute passes
    And an acknowledgement event is received
    Then unscheduled maintenance should be generated
    And 4 email alerts should be queued for imani@example.com
