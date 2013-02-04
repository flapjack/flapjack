@notification_rules @resque
Feature: Notification rules - custom interval per contact,check

Background:
  Given the following users exist:
    | id  | first_name | last_name | email             | sms          |
    | 1   | Malak      | Al-Musawi | malak@example.com | +61400000001 |

  And the following entities exist:
    | id  | name | contacts |
    | 1   | foo  | 1        |
    | 2   | bar  | 2        |
    | 3   | sky  | 1        |

  And user 1 has the following notification intervals:
    | email | sms |
    | 15    | 60  |

  And user 1 has the following notification rules:
    | id | entities | entity_tags | warning_media | critical_media   | warning_blackhole | time_restrictions |
    | 1  | foo      |             | email         | sms,email        |                   | 8-18 weekdays     |
    | 2  | bar      |             | email         | email            |                   |                   |
    | 3  | car      |             |               | sms,email        | true              |                   |

@time_restrictions
Scenario: Alerts only during specified time restrictions
  Given the check is check 'ping' on entity 'foo'
  And   the check is in an ok state
  And   the time is 7am on a Wednesday
  And   a critical event is received
  Then  no email alerts should be queued for malak@example.com
  When  5 minutes passes
  And   a critical event is received
  Then  no email alerts should be queued for malak@example.com
  When  60 minutes passes
  And   a critical event is received
  Then  1 email alert should be queued for malak@example.com

@intervals
Scenario: Alerts according to custom interval
  Given the check is check 'ping' on entity 'bar'
  And   the check is in an ok state
  When  a critical event is received for check 'ping' on entity 'foo'
  Then  no email alerts should be queued for malak@example.com
  When  1 minute passes
  And   a critical event is received for check 'ping' on entity 'foo'
  Then  1 email alert should be queued for malak@example.com
  When  9 minutes passes
  And   a critical event is received for check 'ping' on entity 'foo'
  Then  1 email alert should be queued for malak@example.com

