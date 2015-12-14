@process
Feature: simulate-failed-check command line
  As a systems administrator
  I should be able to use simulate-failed-check
  From the command line

  Background:
    Given a file named "simulate-failed-check.toml" with:
"""
[redis]
  db = 14
  driver = "ruby"
"""

  Scenario: Running with --help shows usage information
    When I run `bundle exec bin/flapjack simulate --help`
    Then the exit status should be 0
    And  the output should contain "Simulates a check by creating a stream of events for Flapjack"
    And  the output should contain "-k arg|--check arg"

  Scenario: Running simulate-failed-check with no arguments exits uncleanly and shows usage
    When I run `bundle exec bin/flapjack simulate`
    Then the exit status should not be 0
    And  the output should contain "Simulates a check by creating a stream of events for Flapjack"

  Scenario: Simulate a failed check
    When I run `bundle exec bin/flapjack -c tmp/cucumber_cli/simulate-failed-check.toml simulate fail -t 0.05 -i 0.05 -k 'test:PING'`
    Then the exit status should be 0
    And  the output should contain "sending failure event"
    And  the output should contain "stopping"

