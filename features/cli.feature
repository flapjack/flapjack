Feature: command line utility
  As a systems administrator
  I should be able to manage Flapjack
  From the command line

  # NB aruba instructions have a working dir of tmp/aruba, while others have
  # the flapjack root directory (and daemons.rb appends bin/ before calling
  # commands)

  Background:
    Given a file named "flapjack_cfg.yml" with:
"""
test:
  redis:
    db: 14
  processor:
    enabled: yes
    logger:
      level: warn
"""
    And a file named "flapjack_cfg_d.yml" with:
"""
test:
  pid_file: flapjack_d.pid
  log_file: flapjack_d.log
  redis:
    db: 14
  processor:
    enabled: yes
    logger:
      level: warn
"""

  @daemon
  Scenario: Starting flapjack
    Given flapjack is not running
    When I start a daemon with `flapjack start --config tmp/aruba/flapjack_cfg.yml`
    And I wait until flapjack is running, for a maximum of 45 seconds
    Then flapjack should be running

  @daemon
  Scenario: Stopping flapjack via SIGINT
    Given flapjack is not running
    When I start a daemon with `flapjack start --config tmp/aruba/flapjack_cfg.yml`
    And I wait until flapjack is running, for a maximum of 45 seconds
    Then flapjack should be running
    When I send a SIGINT to the flapjack process
    And I wait until flapjack is not running, for a maximum of 45 seconds
    Then flapjack should not be running

  Scenario: Starting and stopping flapjack, daemonized
    Given flapjack is not running
    When I run `../../bin/flapjack start -d --config flapjack_cfg_d.yml`
    And I wait until flapjack is running, for a maximum of 45 seconds
    Then flapjack should be running
    When I run `../../bin/flapjack stop --config flapjack_cfg_d.yml`
    And I wait until flapjack is not running, for a maximum of 45 seconds
    Then flapjack should not be running

  Scenario: Starting, restarting and stopping flapjack, daemonized
    Given flapjack is not running
    When I run `../../bin/flapjack start -d --config flapjack_cfg_d.yml`
    And I wait until flapjack is running, for a maximum of 45 seconds
    Then flapjack should be running
    When I run `../../bin/flapjack restart -d --config flapjack_cfg_d.yml`
    And I wait until flapjack is running (restarted), for a maximum of 45 seconds
    Then flapjack should be running (restarted)
    When I run `../../bin/flapjack stop --config flapjack_cfg_d.yml`
    And I wait until flapjack is not running (restarted), for a maximum of 45 seconds
    Then flapjack should not be running (restarted)

  @daemon
  Scenario: Reloading flapjack configuration
    Given flapjack is not running
    When I start a daemon with `flapjack start --config tmp/aruba/flapjack_cfg.yml`
    And I wait until flapjack is running, for a maximum of 45 seconds
    Then flapjack should be running
    When I run `mv flapjack_cfg.yml flapjack_cfg.yml.bak` interactively
    Given a file named "flapjack_cfg.yml" with:
"""
test:
  redis:
    db: 14
  processor:
    enabled: no
"""
    When I send a SIGHUP to the flapjack process
    # TODO how to test for config file change?
    Then flapjack should be running
