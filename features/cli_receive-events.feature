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
    driver: ruby
"""

  Scenario: Running with --help shows usage information
    When I run `bundle exec bin/flapjack -n test receiver mirror --help`
    Then the exit status should be 0
    And  the output should contain "replay the last COUNT events from the source"
    And  the output should contain "-s, --source=arg"

  Scenario: Running receive-events with no arguments exits uncleanly and shows usage
    When I run `bundle exec bin/flapjack -n test receiver mirror`
    Then the exit status should not be 0
    And  the output should contain "error: d is required, i is required, s is required"

    #TODO: put some archived events into a separate redis db and then run receive-events to suck them up

