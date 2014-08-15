@process
Feature: Flapper command line
  As a systems administrator
  I should be able to manage flapper
  From the command line

  Background:
    Given a file named "flapjack_cfg.yaml" with:
"""
test:
  pid_dir: tmp/cucumber_cli/
  log_dir: tmp/cucumber_cli/
  redis:
    db: 14
  processor:
    enabled: yes
    logger:
      level: warn
"""

  Scenario: Running with --help shows usage information
    When I run `bundle exec bin/flapjack --config tmp/cucumber_cli/flapjack_cfg.yaml flapper --help`
    Then the exit status should be 0
    And  the output should contain "Artificial service that oscillates up and down"
    And  the output should contain "[-b arg|--bind-ip arg]"

  Scenario: Starting flapper
    When I start flapper (via bundle exec) with `flapjack --config tmp/cucumber_cli/flapjack_cfg.yaml flapper start --no-daemonize`
    Then flapper should start within 15 seconds

  Scenario: Stopping flapper via SIGINT
    When I start flapper (via bundle exec) with `flapjack --config tmp/cucumber_cli/flapjack_cfg.yaml flapper start --no-daemonize`
    Then flapper should start within 15 seconds
    When I send a SIGINT to the flapper process
    Then flapper should stop within 15 seconds

  Scenario: Starting, status, and stopping flapper, daemonized
    When I start flapper (daemonised) (via bundle exec) with `flapjack --config tmp/cucumber_cli/flapjack_cfg.yaml flapper start -d -p tmp/cucumber_cli/flapper.pid -l tmp/cucumber_cli/flapper.log`
    Then flapper should start within 15 seconds
    When I run `bundle exec bin/flapjack --config tmp/cucumber_cli/flapjack_cfg.yaml flapper status -p tmp/cucumber_cli/flapper.pid`
    Then the exit status should be 0
    And  the output should contain "flapper is running"
    When I stop flapper (via bundle exec) with `flapjack --config tmp/cucumber_cli/flapjack_cfg.yaml flapper stop -p tmp/cucumber_cli/flapper.pid`
    Then flapper should stop within 15 seconds

  Scenario: Starting, restarting and stopping flapper, daemonized
    When I start flapper (daemonised) (via bundle exec) with `flapjack --config tmp/cucumber_cli/flapjack_cfg.yaml flapper start -d -p tmp/cucumber_cli/flapper.pid -l tmp/cucumber_cli/flapper.log`
    Then flapper should start within 15 seconds
    When I restart flapper (daemonised) (via bundle exec) with `flapjack --config tmp/cucumber_cli/flapjack_cfg.yaml flapper restart -p tmp/cucumber_cli/flapper.pid -l tmp/cucumber_cli/flapper.log`
    Then flapper should restart within 15 seconds
    When I stop flapper (via bundle exec) with `flapjack --config tmp/cucumber_cli/flapjack_cfg.yaml flapper stop -p tmp/cucumber_cli/flapper.pid`
    Then flapper should stop within 15 seconds

  Scenario: Getting status when stopped
    When I run `bundle exec bin/flapjack --config tmp/cucumber_cli/flapjack_cfg.yaml flapper status -p tmp/cucumber_cli/flapper.pid`
    Then the exit status should not be 0
    And  the output should contain "flapper is not running"
