Feature: Netsaint -> Flapjack configuration converter
  To assist the migration to Flapjack
  An operator needs to migrate
  A functioning netsaint or nagios configuration
  Into Flapjack's native configuration system

  @parse
  Scenario: Parse + print netsaint services
    Given NetSaint configuration is at "features/support/data/etc/netsaint"
    When I run "flapjack-config-importer print services --source=features/support/data/etc/netsaint"
    Then I should see a valid JSON output
    And I should see a list of services
    And I should see the following attributes for every service:
      | attribute     |
      | check_command |
      | description   |

  @parse
  Scenario: Parse + print netsaint timeperiods
    Given NetSaint configuration is at "features/support/data/etc/netsaint"
    When I run "flapjack-config-importer print timeperiods --source=features/support/data/etc/netsaint"
    Then I should see a valid JSON output
    And I should see a list of timeperiods
    And I should see the following attributes for every timeperiod:
      | attribute        | nillable? |
      | timeperiod_alias | true      |

  @parse
  Scenario: Parse + print netsaint contacts
    Given NetSaint configuration is at "features/support/data/etc/netsaint"
    When I run "flapjack-config-importer print contacts --source=features/support/data/etc/netsaint"
    Then I should see a valid JSON output
    And I should see a list of contacts
    And I should see the following attributes for every contact:
      | attribute                |
      | contact_alias            |
      | email_address            |
      | host_notification_period |
      | host_notify_commands     |
      | notify_host_down         |
      | notify_host_unreachable  |
      | notify_service_warning   |
      | notify_service_recovery  |
      | notify_service_critical  |
      | notify_host_recovery     |
      | service_notify_commands  |
      | svc_notification_period  |
    And I should see the following attributes for every contact:
      | attribute                | nillable? |
      | pager                    | true      |

  @parse
  Scenario: Parse + print netsaint contactgroups
    Given NetSaint configuration is at "features/support/data/etc/netsaint"
    When I run "flapjack-config-importer print contactgroups --source=features/support/data/etc/netsaint"
    Then I should see a valid JSON output
    And I should see a list of contactgroups
    And I should see the following attributes for every contactgroup:
      | attribute   |
      | contacts    |
      | group_alias |

  @parse
  Scenario: Parse + print netsaint hosts
    Given NetSaint configuration is at "features/support/data/etc/netsaint"
    When I run "flapjack-config-importer print hosts --source=features/support/data/etc/netsaint"
    Then I should see a valid JSON output
    And I should see a list of hosts
    And I should see the following attributes for every host:
      | attribute             |
      | host_alias            |
      | address               |
      | parent_hosts          |
      | host_check_command    |
      | max_attempts          |
      | notification_interval |
      | notification_period   |
      | notify_recovery       |
      | notify_down           |
      | notify_unreachable    |
    And I should see the following attributes for every host:
      | attribute                | nillable? |
      | event_handler            | true      |

  @import
  Scenario: Import Netsaint config
    Given NetSaint configuration is at "features/support/data/etc/netsaint"
    And Flapjack is using the Sqlite3 persistence backend
    When I run "flapjack-config-importer" with the following arguments:
      | argument                                      |
      | import                                        |
      | --source=features/support/data/etc/netsaint   |
    When I run "flapjack-batches" with the following arguments:
      | argument                                      |
      | show                                          |
      | --config=features/support/configs/sqlite3.ini |
      | --format=json                                 |
    Then I should see a valid JSON output
    Then I should see a batch of checks in the output
    Then I should see a batch of checks with relationships in the output

  @import
  Scenario: Populate workers with Flapjack-ised Netsaint checks
    Given I run the importer
    And the necessary checks and relationships are created
    When I run "flapjack-populator"
    Then the latest batch of checks should be in the work queue
