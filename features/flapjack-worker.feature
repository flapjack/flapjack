Feature: flapjack-worker
  To be alerted to problems
  A user
  Needs checks executed
  On a regular schedule
  And the results of those checks
  Need to be reported

  Scenario: Start a worker
    Given beanstalkd is running
    When I background run "flapjack-worker"
    Then I should see "flapjack-worker" running
    Then I should see "Waiting for check" in the "flapjack-worker" output

  Scenario: Start a worker without beanstalk running
    Given beanstalkd is running
    Given beanstalkd is not running
    When I background run "flapjack-worker"
    Then I should see "flapjack-worker" running
    Then I should not see "Shutting down" in the "flapjack-worker" output
