@events @processor
Feature: events and check names
  Flapjack must handle weird characters in check names in events

  @time
  Scenario: acknowledgements for checks with colons
    Given the check is check 'Disk C: Utilisation' on entity 'foo-app-01.example.com'
    And   the check is in an ok state
    When  a warning event is received
    Then  no notifications should have been generated
    When  1 minute passes
    And   a warning event is received
    Then  1 notification should have been generated
    When  an acknowledgement event is received
    Then  2 notifications should have been generated
    When  1 minute passes
    And   a warning event is received
    Then  2 notifications should have been generated
