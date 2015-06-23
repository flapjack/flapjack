@process
Feature: Flapper command line
  As a systems administrator
  I should be able to manage flapper
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
    When I run `bundle exec bin/flapjack --config tmp/cucumber_cli/flapjack_cfg.toml flapper --help`
    Then the exit status should be 0
    And  the output should contain "Artificial service that oscillates up and down"
    And  the output should contain "-b, --bind-ip=arg"

  Scenario: Starting flapper
    When I start flapper (via bundle exec) with `flapjack --config tmp/cucumber_cli/flapjack_cfg.toml flapper`
    Then flapper should start within 15 seconds
