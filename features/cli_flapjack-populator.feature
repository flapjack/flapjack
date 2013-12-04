@process
Feature: flapjack-populator command line
  As a systems administrator
  I should be able to use flapjack-populator
  From the command line

  Background:
    Given a file named "flapjack-populator.yaml" with:
"""
test:
  redis:
    db: 14
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
        "interval": "3600",
        "rollup_threshold": "5"
      },
      "email": {
        "address": "ada@example.com",
        "interval": "7200",
        "rollup_threshold": null
      }
    },
    "tags": [
      "legend",
      "first computer programmer"
    ]
  }
]
"""
    And  a file named "flapjack-populator-entities.json" with:
"""
[
  {
    "id": "10001",
    "name": "clientx-app-01",
    "contacts": [
      "362",
      "363",
      "364"
    ],
    "tags": [
      "source:titanium",
      "foo"
    ]
  }
]
"""

  Scenario: Running with --help shows usage information
    When I run `bin/flapjack-populator --help`
    Then the exit status should be 0
    And  the output should contain "Usage: flapjack-populator"
    And  the output should contain "import-contacts"
    And  the output should contain "import-entities"
    And  the output should contain "--config"

  Scenario: Running flapjack-populator with no arguments exits uncleanly and shows usage
    When I run `bin/flapjack-populator`
    Then the exit status should not be 0
    And  the output should contain "Usage: flapjack-populator"

  Scenario: Importing contacts
    When I run `bin/flapjack-populator import-contacts --from tmp/cucumber_cli/flapjack-populator-contacts.json --config tmp/cucumber_cli/flapjack-populator.yaml`
    Then the exit status should be 0

  Scenario: Importing entities
    When I run `bin/flapjack-populator import-entities --from tmp/cucumber_cli/flapjack-populator-entities.json --config tmp/cucumber_cli/flapjack-populator.yaml`
    Then the exit status should be 0

