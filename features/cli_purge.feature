@process
Feature: purge command line
  As a systems administrator
  I should be able to use purge
  From the command line

  Background:
    Given a file named "purge.toml" with:
"""
[redis]
  db = 14
  driver = "ruby"
"""

  Scenario: Running with --help shows usage information
    When I run `bundle exec bin/flapjack purge --help`
    Then the exit status should be 0
    And  the output should contain "Purge data from Flapjack's database"
    And  the output should contain "--check arg"

  Scenario: Running purge with no arguments exits uncleanly and shows usage
    When I run `bundle exec bin/flapjack purge`
    Then the exit status should not be 0
    And  the output should contain "Purge data from Flapjack's database"

  #flapjack purge check_history --days 90
  Scenario: Purge check data older than 90 days
    When I run `bundle exec bin/flapjack -c tmp/cucumber_cli/purge.toml purge check_history --days 90`
    Then the exit status should be 0

  #flapjack purge check_history --days 2 --check "flapper.example:Flapper"
  Scenario: keep only last two days of Flapper state changes

  #flapjack purge check_history --state-changes +10
  Scenario: purge all state changes except the newest 10 for all checks

  #flapjack purge disabled_checks
  Scenario: purge all data about disabled checks

  #flapjack purge stale_checks --days 90
  Scenario: purge all data about checks with no updates in the last 90 days

