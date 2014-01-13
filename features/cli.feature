@process
Feature: command line utility
  As a systems administrator
  I should be able to manage Flapjack
  From the command line

  Background:
    Given a file named "flapjack_cfg.yaml" with:
"""
test:
  redis:
    db: 14
  processor:
    enabled: yes
    logger:
      level: warn
"""
    And a file named "flapjack_cfg_d.yaml" with:
"""
test:
  pid_file: tmp/cucumber_cli/flapjack_d.pid
  log_file: tmp/cucumber_cli/flapjack_d.log
  redis:
    db: 14
  processor:
    enabled: yes
    logger:
      level: warn
"""

  Scenario: Running with --help shows usage information
    When I run `bin/flapjack --help`
    Then the exit status should be 0
    And  the output should contain "Usage: flapjack"
    And  the output should contain " reload "
    And  the output should contain "-c, --config"

  Scenario: Getting status when stopped
    When I run `bin/flapjack status --config tmp/cucumber_cli/flapjack_cfg_d.yaml`
    Then the exit status should not be 0
    And  the output should contain "Flapjack is not running"

  Scenario: Starting flapjack
    When I start flapjack with `flapjack start --config tmp/cucumber_cli/flapjack_cfg.yaml`
    Then flapjack should start within 15 seconds

  Scenario: Stopping flapjack via SIGINT
    When I start flapjack with `flapjack start --config tmp/cucumber_cli/flapjack_cfg.yaml`
    Then flapjack should start within 15 seconds
    When I send a SIGINT to the flapjack process
    Then flapjack should stop within 15 seconds

  Scenario: Starting, status and stopping flapjack, daemonized
    When I start flapjack (daemonised) with `flapjack start -d --config tmp/cucumber_cli/flapjack_cfg_d.yaml`
    Then flapjack should start within 15 seconds
    When I run `bin/flapjack status --config tmp/cucumber_cli/flapjack_cfg_d.yaml`
    Then the exit status should be 0
    And  the output should contain "Flapjack is running"
    When I stop flapjack with `flapjack stop --config tmp/cucumber_cli/flapjack_cfg_d.yaml`
    Then flapjack should stop within 15 seconds

  Scenario: Starting, restarting and stopping flapjack, daemonized
    When I start flapjack (daemonised) with `flapjack start -d --config tmp/cucumber_cli/flapjack_cfg_d.yaml`
    Then flapjack should start within 15 seconds
    When I restart flapjack with `flapjack restart -d --config tmp/cucumber_cli/flapjack_cfg_d.yaml`
    Then flapjack should restart within 15 seconds
    When I stop flapjack with `flapjack stop --config tmp/cucumber_cli/flapjack_cfg_d.yaml`
    Then flapjack should stop within 15 seconds

  Scenario: Reloading flapjack configuration
    When I start flapjack with `flapjack start --config tmp/cucumber_cli/flapjack_cfg.yaml`
    Then flapjack should start within 15 seconds
    When I run `mv tmp/cucumber_cli/flapjack_cfg.yaml tmp/cucumber_cli/flapjack_cfg.yaml.bak`
    Given a file named "flapjack_cfg.yaml" with:
"""
test:
  redis:
    db: 14
  processor:
    enabled: no
"""
    When I send a SIGHUP to the flapjack process
    # TODO how to test for config file change?
    When I stop flapjack with `flapjack stop --config tmp/cucumber_cli/flapjack_cfg_d.yaml`
    Then flapjack should stop within 15 seconds


