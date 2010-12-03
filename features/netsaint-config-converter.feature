Feature: Netsaint -> Flapjack configuration converter
  To sufficiently exercise Flapjack's features
  A functioning netsaint configuration
  Must be routinely imported
  And run in parallel

  Scenario: Parse + print netsaint checks
    Given netsaint configuration is at "/etc/netsaint"
    When I run "flapjack-config-importer --source=/etc/netsaint print checks"
    Then I should see the following terms in the output:
    | term |
    | HOSTAVAIL |
    | HTTP |
    | Process Fingerprint |
    | DISK / Utilisation |
    | RAM Utilisation |
    | SWAP Utilisation |
    | PING Round Trip Time |
    | HTTP Port 80 |
    | SSH |

  Scenario: Import Netsaint config
    Given netsaint configuration is at "/etc/netsaint"
    And Flapjack is installed
    And Flapjack is using the Sqlite3 persistence backend
    When I run "flapjack-config-importer --source=/etc/netsaint"
    Then Flapjack should have a new batch of checks
    And the Flapjack batch should have several checks
    And the Flapjack checks should have relationships

  Scenario: Populate workers with Flapjack-ised Netsaint checks
    Given I run the importer
    And the necessary checks and relationships are created
    When I run "flapjack-populator"
    Then the latest batch of checks should be in the work queue
