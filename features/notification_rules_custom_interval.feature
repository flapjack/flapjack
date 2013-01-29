@notification_rules
Feature: Notification rules - custom interval per contact,check

Background:
  Given the following entities exist:
    | id  | name |
    | 1   | foo  |
    | 2   | bar  |
    | 3   | sky  |
  And the following users exist:
    | id  | first_name | last_name | email            | entities |
    | 1   | Jane       | Smith     | jane@example.com | 1,2,3    |
  And user 1 has the following contact media:
    | email            | sms          | jabber                  |
    | jane@example.com | +61400000001 | jane@jabber.example.com |
  And user 1 has the following notification intervals:
    | email | sms | jabber |
    | 15    | 60  | 10     |
  And user 1 has the following notification rules:
    | id | entities | entity_tags | warning_media | critical_media   | warning_blackhole |
    | 1  | foo      |             | email,jabber  | sms,email,jabber |                   |
    | 2  | bar      |             | email         | email            |                   |
    | 3  | car      |             |               | sms,email,jabber | true              |
  And notification rule 1 has the following time restrictions:
    | start_time | duration | days_of_week                             |
    | 8:00       | 10 hours | monday,tuesday,wednesday,thursday,friday |

Scenario: Alerts only during specified time restrictions
  Given the check is check 'ping' on entity 'foo'
  And   the check is in an ok state
  And   the time is 7am on a Wednesday
  And   a critical event is received
  Then  an email alert should not be queued to jane@example.com
  When  5 minutes passes
  And   a critical event is received
  Then  an email alert should not be queued to jane@example.com
  When  60 minutes passes
  And   a critical event is received
  Then  an email alert should be queued to jane@example.com

Scenario: Alerts according to custom interval
  Given the check is check 'ping' on entity 'foo'
  Given the check is in an ok state
  And   a critical event is received for check 'ping' on entity 'foo'
  Then  an email alert should not be queued to jane@example.com