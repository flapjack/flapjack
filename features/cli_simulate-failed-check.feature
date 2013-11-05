@process
Feature: simulate-failed-check command line
  As a systems administrator
  I should be able to use simulate-failed-check
  From the command line

  Background:
    Given a file named "simulate-failed-check.yaml" with:
"""
test:
  redis:
    db: 14
"""

  Scenario: Running with --help shows usage information
    When I run `bin/simulate-failed-check --help`
    Then the exit status should be 0
    And  the output should contain "Usage: simulate-failed-check"
    And  the output should contain "-k, --check CHECK"

  Scenario: Running simulate-failed-check with no arguments exits uncleanly and shows usage
    When I run `bin/simulate-failed-check`
    Then the exit status should not be 0
    And  the output should contain "Usage: simulate-failed-check"

  Scenario: Simulate a failed check
    When I run `bin/simulate-failed-check fail -c tmp/cucumber_cli/simulate-failed-check.yaml -t 0 -i 0.1 -e 'test' -k 'PING'`
    Then the exit status should be 0
    And  the output should contain "sending failure event"
    And  the output should contain "stopping"

