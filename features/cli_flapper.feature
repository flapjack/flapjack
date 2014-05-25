@process
Feature: Flapper command line
  As a systems administrator
  I should be able to manage flapper
  From the command line

  Scenario: Running with --help shows usage information
    When I run `bundle exec bin/flapjack flapper --help`
    Then the exit status should be 0
    And  the output should contain "Artificial service that oscillates up and down"
    And  the output should contain "[-b arg|--bind-ip arg]"

  Scenario: Starting flapper
    When I start flapper (via bundle exec) with `flapjack flapper start --no-daemonize`
    Then flapper should start within 15 seconds

  Scenario: Stopping flapper via SIGINT
    When I start flapper (via bundle exec) with `flapjack flapper start --no-daemonize`
    Then flapper should start within 15 seconds
    When I send a SIGINT to the flapper process
    Then flapper should stop within 15 seconds

  Scenario: Starting, status, and stopping flapper, daemonized
    When I start flapper (daemonised) (via bundle exec) with `flapjack flapper start -d -p tmp/cucumber_cli/flapper_d.pid -l tmp/cucumber_cli/flapper_d.log`
    Then flapper should start within 15 seconds
    When I run `bundle exec bin/flapjack flapper status -p tmp/cucumber_cli/flapper_d.pid`
    Then the exit status should be 0
    And  the output should contain "flapper is running"
    When I stop flapper (via bundle exec) with `flapjack flapper stop -p tmp/cucumber_cli/flapper_d.pid`
    Then flapper should stop within 15 seconds

  Scenario: Starting, restarting and stopping flapper, daemonized
    When I start flapper (daemonised) (via bundle exec) with `flapjack flapper start -d -p tmp/cucumber_cli/flapper_d.pid -l tmp/cucumber_cli/flapper_d.log`
    Then flapper should start within 15 seconds
    When I restart flapper (daemonised) (via bundle exec) with `flapjack flapper restart -d -p tmp/cucumber_cli/flapper_d.pid -l tmp/cucumber_cli/flapper_d.log`
    Then flapper should restart within 15 seconds
    When I stop flapper (via bundle exec) with `flapjack flapper stop -p tmp/cucumber_cli/flapper_d.pid`
    Then flapper should stop within 15 seconds

  Scenario: Getting status when stopped
    When I run `bundle exec bin/flapjack flapper status -p tmp/cucumber_cli/flapper_d.pid`
    Then the exit status should not be 0
    And  the output should contain "flapper is not running"


