@process
Feature: flapjack-populator command line
  As a systems administrator
  I should be able to use flapjack-populator
  From the command line

  Background:
    Given a file named "flapjack-populator.toml" with:
"""
[redis]
  db = 14
  driver = "ruby"
"""
    And  a file named "flapjack-populator-contacts.json" with:
"""
[
  {
    "id": "21",
    "first_name": "Ada",
    "last_name": "Lovelace",
    "email": "ada@example.com",
    "media": {
      "sms": {
        "address": "+61412345678",
        "interval": 3600,
        "rollup_threshold": 5
      },
      "email": {
        "address": "ada@example.com",
        "interval": 7200,
        "rollup_threshold": null
      }
    }
  }
]
"""

  Scenario: Running with --help shows usage information
    When I run `bundle exec bin/flapjack import --help`
    Then the exit status should be 0
    And  the output should contain "Bulk import data from an external source"
    And  the output should contain "import contacts"
    And  the output should contain "[-f arg|--from arg]"

  Scenario: Running flapjack-populator with no arguments exits uncleanly and shows usage
    When I run `bundle exec bin/flapjack import`
    Then the exit status should not be 0
    And  the output should contain "Bulk import data from an external source"

  Scenario: Importing contacts
    When I run `bundle exec bin/flapjack --config tmp/cucumber_cli/flapjack-populator.toml import contacts --from tmp/cucumber_cli/flapjack-populator-contacts.json`
    Then the exit status should be 0

  Scenario Outline: Running an flapjack-populator import command with a missing '--from' exits uncleanly and shows usage
    When I run `bundle exec bin/flapjack --config tmp/cucumber_cli/flapjack-populator.toml import <Type> example.json`
    Then the exit status should not be 0
    And  the output should contain "error: f is required"
    And  the output should contain "Bulk import data from an external source"
    Examples:
      | Type     |
      | contacts |
