Feature: CouchDB persistence backend
  To use a CouchDB backend with Flapjack
  The backend must conform 
  To the persistence API

  Background:
    Given I set up the Couch backend with the following options:
      | host      | port | database      |
      | localhost | 5984 | flapjack_test | 

  Scenario: Create a check
    When I create the following checks:
      | name     | id | command | status | enabled |
      | passing  | 1  | exit 0  | 0      | true    |
      | warning  | 2  | exit 1  | 1      | true    |
      | critical | 3  | exit 2  | 2      | true    |
    Then looking up the following checks should return documents:
      | id | 
      | 1  |
      | 2  |
      | 3  |

  Scenario: Update a check
    Given the following checks exist:
      | name     | id | command | status | enabled |
      | passing  | 4  | exit 0  | 0      | true    |
    When I update the following checks:
      | name     | id | command | status | enabled |
      | passing  | 4  | exit 2  | 2      | true    |
    Then the updates should succeed

  Scenario: Delete a check
    Given the following checks exist:
      | name     | id | command | status | enabled |
      | passing  | 5  | exit 0  | 0      | true    |
    When I delete the check with id "4"
    Then the check with id "4" should not exist

  Scenario: List all checks
    Given the following checks exist:
      | name     | id | command | status | enabled |
      | passing  | 6  | exit 0  | 0      | true    |
      | warning  | 7  | exit 1  | 1      | true    |
      | critical | 8  | exit 2  | 2      | true    |
    When I get all checks
    Then I should have at least 3 checks

  Scenario: Query for failing parents
    Given the following checks exist:
      | name           | id | command | status | enabled |
      | failing parent | 1  | exit 2  | 2      | true    |
      | passing child  | 2  | exit 0  | 0      | true    |
    And the following related checks exist: 
      | id | parent_id | child_id |
      | 1  | 1         | 2        |
    Then the following result should not have a failing parent:
      | check_id | 
      | 1        |
    Then the following result should have a failing parent:
      | check_id |
      | 2        |

  Scenario: Saving events
    Given the following checks exist: 
      | name           | id | command | status | enabled |
      | failing parent | 4  | exit 2  | 4      | true    |
    Then the following event should save:
      | check_id | status |
      | 4        | 2      |
    And the check with id "4" on the Sqlite3 backend should have an event created

  Scenario: List events for a check
    Given the following checks exist: 
      | name           | id | command | status | enabled |
      | passing child  | 12 | exit 2  | 3      | true    |
    Given the following events exist: 
      | check_id |
      | 12       |
      | 12       |
      | 12       |
    When I get all events for check "12"
    Then I should have at least 3 events

  Scenario: List all events
    Given the following events exist: 
      | check_id |
      | 9        |
      | 10       |
      | 11       |
    When I get all events
    Then I should have at least 3 events

  Scenario: List all check relationships
    Given the following checks exist: 
      | name     | id | command | status | enabled |
      | passing  | 9  | exit 0  | 0      | true    |
      | warning  | 10 | exit 1  | 1      | true    |
      | critical | 11 | exit 2  | 2      | true    |
    And the following related checks exist: 
      | parent_id | child_id |
      | 9         | 10       |
      | 10        | 11       |
      | 11        | 9        |
    When I get all check relationships
    Then I should have at least 3 check relationships
