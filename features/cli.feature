@process
Feature: command line utility
  As a systems administrator
  I should be able to manage Flapjack
  From the command line

  Background:
    Given a file named "flapjack_cfg.toml" with:
"""
pid_dir = "tmp/cucumber_cli/"
log_dir = "tmp/cucumber_cli/"
[redis]
  db = 14
[processor]
  enabled = "yes"
  [processor.logger]
    level = "warn"
"""
    And a file named "flapjack_cfg_d.toml" with:
"""
pid_dir = "tmp/cucumber_cli/"
log_dir = "tmp/cucumber_cli/"
[redis]
  db = 14
[processor]
  enabled = "yes"
  [processor.logger]
    level = "warn"
"""

  Scenario: Running with --help shows usage information
    When I run `bundle exec bin/flapjack server --help`
    Then the exit status should be 0
    And  the output should contain "Server for running components"
    And  the output should contain " reload "
    And  the output should contain "[-d|--daemonize]"

  Scenario: Getting status when stopped
    When I run `bundle exec bin/flapjack -n test --config tmp/cucumber_cli/flapjack_cfg_d.toml server status`
    Then the exit status should not be 0
    And  the output should contain "Flapjack is not running"

  Scenario: Starting flapjack
    When I start flapjack (via bundle exec) with `flapjack -n test --config tmp/cucumber_cli/flapjack_cfg.toml server start`
    Then flapjack should start within 15 seconds

  Scenario: Stopping flapjack via SIGINT
    When I start flapjack (via bundle exec) with `flapjack -n test --config tmp/cucumber_cli/flapjack_cfg.toml server start`
    Then flapjack should start within 15 seconds
    When I send a SIGINT to the flapjack process
    Then flapjack should stop within 15 seconds

  Scenario: Starting, status and stopping flapjack, daemonized
    When I start flapjack (daemonised) (via bundle exec) with `flapjack -n test --config tmp/cucumber_cli/flapjack_cfg_d.toml server start`
    Then flapjack should start within 15 seconds
    When I run `bundle exec bin/flapjack -n test --config tmp/cucumber_cli/flapjack_cfg_d.toml server status`
    Then the exit status should be 0
    And  the output should contain "Flapjack is running"
    When I stop flapjack (via bundle exec) with `flapjack -n test --config tmp/cucumber_cli/flapjack_cfg_d.toml server stop`
    Then flapjack should stop within 15 seconds

  Scenario: Starting, restarting and stopping flapjack, daemonized
    When I start flapjack (daemonised) (via bundle exec) with `flapjack -n test --config tmp/cucumber_cli/flapjack_cfg_d.toml server start`
    Then flapjack should start within 15 seconds
    When I restart flapjack (via bundle exec) with `flapjack -n test --config tmp/cucumber_cli/flapjack_cfg_d.toml server restart`
    Then flapjack should restart within 15 seconds
    When I stop flapjack (via bundle exec) with `flapjack -n test --config tmp/cucumber_cli/flapjack_cfg_d.toml server stop`
    Then flapjack should stop within 15 seconds

  Scenario: Reloading flapjack configuration
    When I start flapjack (via bundle exec) with `flapjack -n test --config tmp/cucumber_cli/flapjack_cfg.toml server start`
    Then flapjack should start within 15 seconds
    When I run `mv tmp/cucumber_cli/flapjack_cfg.toml tmp/cucumber_cli/flapjack_cfg.toml.bak`
    Given a file named "flapjack_cfg.toml" with:
"""
test:
  pid_dir: tmp/cucumber_cli/
  log_dir: tmp/cucumber_cli/
  redis:
    db: 14
  processor:
    enabled: no
"""
    When I send a SIGHUP to the flapjack process
    # TODO how to test for config file change?
    When I stop flapjack (via bundle exec) with `flapjack -n test --config tmp/cucumber_cli/flapjack_cfg_d.toml server stop`
    Then flapjack should stop within 15 seconds
