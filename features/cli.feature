@process
Feature: command line utility
  As a systems administrator
  I should be able to manage Flapjack
  From the command line

  Background:
    Given a file named "flapjack_cfg.yaml" with:
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
    When I run `bundle exec bin/flapjack server --help`
    Then the exit status should be 0
    And  the output should contain "Server for running components"
    And  the output should contain " reload "
    And  the output should contain "[-d|--debug]"

  Scenario: Getting status when stopped
    When I run `bundle exec bin/flapjack -n test --config tmp/cucumber_cli/flapjack_cfg_d.yaml server status`
    Then the exit status should not be 0
    And  the output should contain "Flapjack is not running"

  Scenario: Starting flapjack
    When I start flapjack (via bundle exec) with `flapjack -n test --config tmp/cucumber_cli/flapjack_cfg.yaml server start`
    Then flapjack should start within 15 seconds

  Scenario: Stopping flapjack via SIGINT
    When I start flapjack (via bundle exec) with `flapjack -n test --config tmp/cucumber_cli/flapjack_cfg.yaml server start`
    Then flapjack should start within 15 seconds
    When I send a SIGINT to the flapjack process
    Then flapjack should stop within 15 seconds

  Scenario: Starting, status and stopping flapjack, debug mode
    When I start flapjack (in debug mode) (via bundle exec) with `flapjack -n test --config tmp/cucumber_cli/flapjack_cfg_d.yaml server start -d`
    Then flapjack should start within 15 seconds
    When I run `bundle exec bin/flapjack -n test --config tmp/cucumber_cli/flapjack_cfg_d.yaml server status`
    Then the exit status should be 0
    And  the output should contain "Flapjack is running"
    When I stop flapjack (via bundle exec) with `flapjack -n test --config tmp/cucumber_cli/flapjack_cfg_d.yaml server stop`
    Then flapjack should stop within 15 seconds

  Scenario: Starting, restarting and stopping flapjack, debug mode
    When I start flapjack (in debug mode) (via bundle exec) with `flapjack -n test --config tmp/cucumber_cli/flapjack_cfg_d.yaml server start -d`
    Then flapjack should start within 15 seconds
    When I restart flapjack (via bundle exec) with `flapjack -n test --config tmp/cucumber_cli/flapjack_cfg_d.yaml server restart`
    Then flapjack should restart within 15 seconds
    When I stop flapjack (via bundle exec) with `flapjack -n test --config tmp/cucumber_cli/flapjack_cfg_d.yaml server stop`
    Then flapjack should stop within 15 seconds

  Scenario: Reloading flapjack configuration
    When I start flapjack (via bundle exec) with `flapjack -n test --config tmp/cucumber_cli/flapjack_cfg.yaml server start`
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
    When I stop flapjack (via bundle exec) with `flapjack -n test --config tmp/cucumber_cli/flapjack_cfg_d.yaml server stop`
    Then flapjack should stop within 15 seconds
