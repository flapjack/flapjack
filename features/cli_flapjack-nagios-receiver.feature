@process
Feature: nagios-receiver command line
  As a systems administrator
  I should be able to manage nagios-receiver
  From the command line

  Background:
    Given a fifo named "tmp/cucumber_cli/nagios_perfdata.fifo" exists
    And   a file named "nagios-receiver.yaml" with:
"""
test:
  pid_dir: "tmp/cucumber_cli/"
  log_dir: "tmp/cucumber_cli/"
  redis:
    db: 14
  nagios-receiver:
    fifo: "tmp/cucumber_cli/nagios_perfdata.fifo"
    pid_dir: "tmp/cucumber_cli/"
    log_dir: "tmp/cucumber_cli/"
"""

  Scenario: Running with --help shows usage information
    When I run `bundle exec bin/flapjack receiver nagios --help`
    Then the exit status should be 0
    And  the output should contain "[-f arg|--fifo arg]"
    And  the output should contain "receiver nagios start [-d|--daemonize]"

  Scenario: Starting nagios-receiver
    When I start nagios-receiver (via bundle exec) with `flapjack -n test --config tmp/cucumber_cli/nagios-receiver.yaml receiver start --no-daemonize`
    Then nagios-receiver should start within 15 seconds

  Scenario: Stopping nagios-receiver via SIGINT
    When I start nagios-receiver (via bundle exec) with `flapjack -n test --config tmp/cucumber_cli/nagios-receiver.yaml receiver nagios start --no-daemonize`
    Then nagios-receiver should start within 15 seconds
    When I send a SIGINT to the nagios-receiver process
    Then nagios-receiver should stop within 15 seconds

  Scenario: Starting, status, and stopping nagios-receiver, daemonized
    When I start nagios-receiver (daemonised) (via bundle exec) with `flapjack -n test --config tmp/cucumber_cli/nagios-receiver.yaml receiver nagios start -d`
    Then nagios-receiver should start within 15 seconds
    When I run `bundle exec bin/flapjack -n test --config tmp/cucumber_cli/nagios-receiver.yaml receiver nagios status`
    Then the exit status should be 0
    And  the output should contain "nagios-receiver is running"
    When I stop nagios-receiver (via bundle exec) with `flapjack -n test --config tmp/cucumber_cli/nagios-receiver.yaml receiver nagios stop`
    Then nagios-receiver should stop within 15 seconds

  Scenario: Starting, restarting and stopping nagios-receiver, daemonized
    When I start nagios-receiver (daemonised) (via bundle exec) with `flapjack  -n test --config tmp/cucumber_cli/nagios-receiver.yaml receiver nagios start -d`
    Then nagios-receiver should start within 15 seconds
    When I restart nagios-receiver (daemonised) (via bundle exec) with `flapjack -n test --config tmp/cucumber_cli/nagios-receiver.yaml receiver nagios restart`
    Then nagios-receiver should restart within 15 seconds
    When I stop nagios-receiver (via bundle exec) with `flapjack -n test --config tmp/cucumber_cli/nagios-receiver.yaml receiver nagios stop`
    Then nagios-receiver should stop within 15 seconds

  Scenario: Getting status when stopped
    When I run `bundle exec bin/flapjack -n test --config tmp/cucumber_cli/nagios-receiver.yaml receiver nagios status`
    Then the exit status should not be 0
    And  the output should contain "nagios-receiver is not running"
