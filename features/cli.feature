@process
Feature: command line utility
  As a systems administrator
  I should be able to manage Flapjack
  From the command line

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
  pid_file: tmp/cucumber_cli/flapjack_d.pid
  log_file: tmp/cucumber_cli/flapjack_d.log
  redis:
    db: 14
  processor:
    enabled: yes
    logger:
      level: warn
"""

  Scenario: Starting flapjack
    When I start flapjack with `flapjack start --config tmp/cucumber_cli/flapjack_cfg.yml`
    Then flapjack should start within 15 seconds

  Scenario: Stopping flapjack via SIGINT
    When I start flapjack with `flapjack start --config tmp/cucumber_cli/flapjack_cfg.yml`
    Then flapjack should start within 15 seconds
    When I send a SIGINT to the flapjack process
    Then flapjack should stop within 15 seconds

  Scenario: Starting and stopping flapjack, daemonized
    When I start flapjack (daemonised) with `flapjack start -d --config tmp/cucumber_cli/flapjack_cfg_d.yml`
    Then flapjack should start within 15 seconds
    When I stop flapjack with `flapjack stop --config tmp/cucumber_cli/flapjack_cfg_d.yml`
    Then flapjack should stop within 15 seconds

  Scenario: Starting, restarting and stopping flapjack, daemonized
    When I start flapjack (daemonised) with `flapjack start -d --config tmp/cucumber_cli/flapjack_cfg_d.yml`
    Then flapjack should start within 15 seconds
    When I restart flapjack with `flapjack restart -d --config tmp/cucumber_cli/flapjack_cfg_d.yml`
    Then flapjack should restart within 15 seconds
    When I stop flapjack with `flapjack stop --config tmp/cucumber_cli/flapjack_cfg_d.yml`
    Then flapjack should stop within 15 seconds

  Scenario: Reloading flapjack configuration
    When I start flapjack with `flapjack start --config tmp/cucumber_cli/flapjack_cfg.yml`
    When I run `mv tmp/cucumber_cli/flapjack_cfg.yml tmp/cucumber_cli/flapjack_cfg.yml.bak`
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
    When I send a SIGINT to the flapjack process
    Then flapjack should stop within 15 seconds
