@process
Feature: receive-events command line
  As a systems administrator
  I should be able to use receive-events
  From the command line

  Background:
    Given a file named "receive-events.yaml" with:
"""
test:
  redis:
    db: 14
"""

  Scenario: Running with --help shows usage information
    When I run `bin/receive-events --help`
    Then the exit status should be 0
    And  the output should contain "Usage: receive-events"
    And  the output should contain "-s, --source URL"

  Scenario: Running receive-events with no arguments exits uncleanly and shows usage
    When I run `bin/receive-events`
    Then the exit status should not be 0
    And  the output should contain "Usage: receive-events"

    #TODO: put some archived events into a separate redis db and then run receive-events to suck them up

