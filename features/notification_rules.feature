@notification_rules @processor @notifier
Feature: Notification rules on a per contact basis

  Background:
    Given the following contacts exist:
      | id                                   | name            | timezone       |
      | 7f96a216-76aa-45fc-a88e-7431cd6d7aac | Malak Al-Musawi | Asia/Baghdad   |
      | 65d32027-1942-43b3-93c5-52f4b12d36b0 | Imani Farooq    | Europe/Moscow  |
      | 9f77502c-1daf-47a2-b806-f3ae7d04cefb | Vera Дурейко    | Europe/Paris   |
      | 158ec8fd-36ca-4d10-a2f4-dc04d374e321 | Lucia Moretti   | Europe/Rome    |
      | 5da490ec-72a0-42b0-834f-4049867dfce7 | Wang Fang Wong  | Asia/Shanghai  |

    And the following media exist:
      | id                                   | contact_id                           | transport | address           | interval | rollup_threshold |
      | 28032dbf-388d-4f52-91b2-dc5e5be2becc | 7f96a216-76aa-45fc-a88e-7431cd6d7aac | email     | malak@example.com | 15       | 5                |
      | 73e2803f-948e-467a-a707-37b9f53ee21a | 7f96a216-76aa-45fc-a88e-7431cd6d7aac | sms       | +61400000001      | 60       | 5                |
      | 1d473cef-5369-4396-9f59-533f3db6c1cb | 65d32027-1942-43b3-93c5-52f4b12d36b0 | email     | imani@example.com | 15       | 5                |
      | 7f96a216-76aa-45fc-a88e-7431cd6d7aac | 65d32027-1942-43b3-93c5-52f4b12d36b0 | sms       | +61400000002      | 60       | 5                |
      | 65d32027-1942-43b3-93c5-52f4b12d36b0 | 9f77502c-1daf-47a2-b806-f3ae7d04cefb | email     | vera@example.com  | 15       | 5                |
      | 55d3778e-e4b2-4dcc-8337-03fcbd2e5f80 | 9f77502c-1daf-47a2-b806-f3ae7d04cefb | sms       | +61400000003      | 60       | 5                |
      | 19ef48b1-9a42-488b-9734-00314c79e5eb | 158ec8fd-36ca-4d10-a2f4-dc04d374e321 | email     | lucia@example.com | 15       | 5                |
      | ad25c952-c300-4285-9301-ef4408c9d645 | 158ec8fd-36ca-4d10-a2f4-dc04d374e321 | sms       | +61400000004      | 60       | 5                |
      | f15078cf-3643-4cf1-b701-ac9fe2836365 | 5da490ec-72a0-42b0-834f-4049867dfce7 | email     | fang@example.com  | 15       | 5                |
      | 862228f8-fc80-4887-bc4c-e133fcda4107 | 5da490ec-72a0-42b0-834f-4049867dfce7 | sms       | +61400000005      | 60       | 5                |

    And the following checks exist:
      | id                                   | name     | tags      |
      | 56c13ce2-f246-4bc6-adfa-2206789c3ced | foo:ping | foo,ping  |
      | d1a39575-0480-4f65-a7f7-64c90db93731 | bar:ping | bar,ping  |
      | 2ae8327c-ecf3-4544-ac3e-9c7779503a4a | baz:ping | baz,ping  |
      | 982fc9fb-fbf8-44cd-b6de-6ccbab8e7230 | buf:ping | buf,ping  |

    And the following rules exist:
      | id                                   | contact_id                           | tags     | condition        | time_restrictions | media_ids                                                                 |
      | b0c8deb9-b8c8-4fdd-acc4-72493852ca15 | 7f96a216-76aa-45fc-a88e-7431cd6d7aac | foo,ping | critical         | 8-18 weekdays     | 28032dbf-388d-4f52-91b2-dc5e5be2becc                                      |
      | 2df6bbc4-d6a4-4f23-b6e5-5c4a07c6e686 | 65d32027-1942-43b3-93c5-52f4b12d36b0 | bar,ping | critical,unknown |                   | 1d473cef-5369-4396-9f59-533f3db6c1cb                                      |
      | fc2d1b1f-1480-45dd-814b-4655bc5b1474 | 9f77502c-1daf-47a2-b806-f3ae7d04cefb | foo,ping | critical         |                   | 65d32027-1942-43b3-93c5-52f4b12d36b0                                      |
      | 7c123a29-1a67-4a32-b38e-2658e63834d8 | 9f77502c-1daf-47a2-b806-f3ae7d04cefb | foo,ping |                  |                   | 55d3778e-e4b2-4dcc-8337-03fcbd2e5f80                                      |
      | e8a67e7c-4f3d-4d9b-afe4-ef276bbeb0df | 158ec8fd-36ca-4d10-a2f4-dc04d374e321 | baz,ping | critical         | 8-18 weekdays     | 19ef48b1-9a42-488b-9734-00314c79e5eb,ad25c952-c300-4285-9301-ef4408c9d645 |
      | 0a3c66f2-6245-49cf-a02c-28d586b2f55a | 158ec8fd-36ca-4d10-a2f4-dc04d374e321 | baz,ping | warning          | 8-18 weekdays     | 19ef48b1-9a42-488b-9734-00314c79e5eb                                      |
      | 9b437f3e-4b48-4516-8067-a57935684777 | 7f96a216-76aa-45fc-a88e-7431cd6d7aac | buf,ping | critical         |                   | 28032dbf-388d-4f52-91b2-dc5e5be2becc                                      |
      | 724bf183-215c-4ba9-b835-56db781c4844 | 5da490ec-72a0-42b0-834f-4049867dfce7 |          |                  |                   | f15078cf-3643-4cf1-b701-ac9fe2836365                                      |
      | 1c501800-6b20-458d-bb99-a78d17397c00 | 5da490ec-72a0-42b0-834f-4049867dfce7 |          |                  |                   | 862228f8-fc80-4887-bc4c-e133fcda4107                                      |

    And the following blackholes exist:
      | id                                   | contact_id                           | tags     | condition        | time_restrictions | media_ids                                                                 |
      | dd7005b9-d30b-4875-9e83-dec7fb70895c | 7f96a216-76aa-45fc-a88e-7431cd6d7aac | buf,ping |                  |                   | 28032dbf-388d-4f52-91b2-dc5e5be2becc                                      |

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
    When  a critical event is received
    Then  2 email alerts should be queued for malak@example.com
    When  the time is February 1 2013 17:59
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
    When  a critical event is received
    Then  2 sms alerts should be queued for +61400000004
    When  the time is February 1 2013 17:59
    When  a critical event is received
    Then  3 sms alerts should be queued for +61400000004
    When  the time is February 1 2013 18:01
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
