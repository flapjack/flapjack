@notification_rules @resque
Feature: Notification rules on a per contact basis

  Background:
    Given the following users exist:
      | id  | first_name | last_name | email             | sms          |
      | 1   | Malak      | Al-Musawi | malak@example.com | +61400000001 |
      | 2   | Imani      | Farooq    | imani@example.com | +61400000002 |

    And the following entities exist:
      | id  | name | contacts |
      | 1   | foo  | 1        |
      | 2   | bar  | 1,2      |

    And user 1 has the following notification intervals:
      | email | sms |
      | 15    | 60  |

    And user 1 has the following notification rules:
      | id | entities | entity_tags | warning_media | critical_media   | warning_blackhole | critical_blackhole | time_restrictions |
      | 1  | foo      |             | email         | sms,email        |                   |                    | 8-18 weekdays     |
      | 2  | bar      |             |               | sms,email        | true              |                    |                   |

  @time_restrictions
  @time
  Scenario: Alerts only during specified time restrictions
    Given the check is check 'ping' on entity 'foo'
    And   the check is in an ok state
    And   the timezone is America/New_York
    And   the time is February 1 2013 6:59
    And   a critical event is received
    Then  no email alerts should be queued for malak@example.com
    And   the time is February 1 2013 7:01
    And   a critical event is received
    Then  no email alerts should be queued for malak@example.com
    And   the time is February 1 2013 8:01
    And   a critical event is received
    Then  1 email alert should be queued for malak@example.com
    When  the time is February 1 2013 12:00
    And   all alert dropping keys for user 1 have expired
    And   a critical event is received
    Then  2 email alerts should be queued for malak@example.com
    When  the time is February 1 2013 17:59
    And   all alert dropping keys for user 1 have expired
    And   a critical event is received
    Then  3 email alerts should be queued for malak@example.com
    When  the time is February 1 2013 18:01
    And   all alert dropping keys for user 1 have expired
    And   a critical event is received
    Then  3 email alerts should be queued for malak@example.com

  Scenario: time restrictions continue to work as expected when a contact changes timezone

  @severity
  @time
  Scenario: Don't alert when media,severity does not match any matching rule's severity's media
    Given the check is check 'ping' on entity 'bar'
    And   the check is in an ok state
    When  a warning event is received
    And   60 minutes passes
    And   a warning event is received
    Then  no email alerts should be queued for malak@example.com

  @severity
  @time
  Scenario: Alerts only when media,severity matches any matching rule's severity's media with ok->warning->critical
    Given the check is check 'ping' on entity 'bar'
    And   the check is in an ok state
    When  a warning event is received
    And   1 minute passes
    And   a warning event is received
    Then  no email alerts should be queued for malak@example.com
    When  a critical event is received
    And   5 minute passes
    And   a critical event is received
    Then  1 email alert should be queued for malak@example.com

  @blackhole
  Scenario: Drop alerts matching a blackhole rule

  @intervals
  @time
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
    And   the email alert block for user 1 for the check for state critical expires
    And   a critical event is received
    Then  2 email alerts should be queued for malak@example.com

