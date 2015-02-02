@process
Feature: nagios-receiver command line
  As a systems administrator
  I should be able to manage nagios-receiver
  From the command line

  Background:
    Given a fifo named "tmp/cucumber_cli/nagios_perfdata.fifo" exists
    And   a file named "nagios-receiver.toml" with:
"""
pid_dir = "tmp/cucumber_cli/"
log_dir = "tmp/cucumber_cli/"
[redis]
  db = 14
[nagios-receiver]
  fifo = "tmp/cucumber_cli/nagios_perfdata.fifo"
  pid_dir = "tmp/cucumber_cli/"
  log_dir = "tmp/cucumber_cli/"
"""

  Scenario: Running with --help shows usage information
    When I run `bundle exec bin/flapjack receiver nagios --help`
    Then the exit status should be 0
    And  the output should contain "receiver nagios"
    And  the output should contain "-f, --fifo=arg"

  Scenario: Starting nagios-receiver
    When I start nagios-receiver (via bundle exec) with `flapjack --config tmp/cucumber_cli/nagios-receiver.toml receiver nagios`
    Then nagios-receiver should start within 15 seconds
