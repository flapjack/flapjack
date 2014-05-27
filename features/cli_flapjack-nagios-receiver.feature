@process
Feature: flapjack-nagios-receiver command line
  As a systems administrator
  I should be able to manage flapjack-nagios-receiver
  From the command line

  Background:
    Given a fifo named "tmp/cucumber_cli/nagios_perfdata.fifo" exists
    And   a file named "flapjack-nagios-receiver.yaml" with:
"""
test:
  redis:
    db: 14
  nagios-receiver:
    fifo: "tmp/cucumber_cli/nagios_perfdata.fifo"
"""
    And a file named "flapjack-nagios-receiver_d.yaml" with:
"""
test:
  redis:
    db: 14
  nagios-receiver:
    fifo: "tmp/cucumber_cli/nagios_perfdata.fifo"
    pid_file: "tmp/cucumber_cli/flapjack-nagios-receiver_d.pid"
    log_file: "tmp/cucumber_cli/flapjack-nagios-receiver_d.log"
"""

  Scenario: Running with --help shows usage information
    When I run `bundle exec bin/flapjack receiver nagios --help`
    Then the exit status should be 0
    And  the output should contain "Usage: flapjack-nagios-receiver"
    And  the output should contain "-f, --fifo FIFO"
    And  the output should contain "Required Nagios Configuration Changes"

  Scenario: Starting flapjack-nagios-receiver
    When I start flapjack-nagios-receiver (via bundle exec) with `flapjack -n test --config tmp/cucumber_cli/flapjack-nagios-receiver.yaml receiver start --no-daemonize`
    Then flapjack-nagios-receiver should start within 15 seconds

  Scenario: Stopping flapjack-nagios-receiver via SIGINT
    When I start flapjack-nagios-receiver (via bundle exec) with `flapjack -n test --config tmp/cucumber_cli/flapjack-nagios-receiver.yaml receiver nagios start --no-daemonize`
    Then flapjack-nagios-receiver should start within 15 seconds
    When I send a SIGINT to the flapjack-nagios-receiver process
    Then flapjack-nagios-receiver should stop within 15 seconds

  Scenario: Starting, status, and stopping flapjack-nagios-receiver, daemonized
    When I start flapjack-nagios-receiver (daemonised) (via bundle exec) with `flapjack -n test --config tmp/cucumber_cli/flapjack-nagios-receiver_d.yaml receiver nagios start -d`
    Then flapjack-nagios-receiver should start within 15 seconds
    When I run `bundle exec bin/flapjack -n test --config tmp/cucumber_cli/flapjack-nagios-receiver_d.yaml receiver nagios status`
    Then the exit status should be 0
    And  the output should contain "flapjack-nagios-receiver is running"
    When I stop flapjack-nagios-receiver (via bundle exec) with `flapjack -n test --config tmp/cucumber_cli/flapjack-nagios-receiver_d.yaml receiver nagios stop `
    Then flapjack-nagios-receiver should stop within 15 seconds

  Scenario: Starting, restarting and stopping flapjack-nagios-receiver, daemonized
    When I start flapjack-nagios-receiver (daemonised) (via bundle exec) with `flapjack  -n test --config tmp/cucumber_cli/flapjack-nagios-receiver_d.yaml receiver nagios start -d`
    Then flapjack-nagios-receiver should start within 15 seconds
    When I restart flapjack-nagios-receiver (daemonised) (via bundle exec) with `flapjack -n test --config tmp/cucumber_cli/flapjack-nagios-receiver_d.yaml receiver nagios restart -d`
    Then flapjack-nagios-receiver should restart within 15 seconds
    When I stop flapjack-nagios-receiver (via bundle exec) with `flapjack -n test --config  --config tmp/cucumber_cli/flapjack-nagios-receiver_d.yaml receiver nagios stop`
    Then flapjack-nagios-receiver should stop within 15 seconds

  Scenario: Getting status when stopped
    When I run `bundle exec bin/flapjack -n test --config tmp/cucumber_cli/flapjack-nagios-receiver_d.yaml receiver nagios status`
    Then the exit status should not be 0
    And  the output should contain "flapjack-nagios-receiver is not running"


