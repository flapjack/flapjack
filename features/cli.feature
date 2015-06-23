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
  enabled = true
  [processor.logger]
    level = "warn"
"""

  Scenario: Running with --help shows usage information
    When I run `bundle exec bin/flapjack server --help`
    Then the exit status should be 0
    And  the output should contain "Server for running components"
    And  the output should contain "flapjack [global options] server"

  Scenario: Starting flapjack
    When I start flapjack (via bundle exec) with `flapjack --config tmp/cucumber_cli/flapjack_cfg.toml server`
    Then flapjack should start within 15 seconds

