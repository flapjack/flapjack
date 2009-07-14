Feature: flapjack-worker-manager
  To process multiple checks efficiently 
  A user
  Must run a cluster of workers

  Scenario: Running multiple workers
    Given the flapjack-worker-manager is on my path
    And there are no instances of flapjack-worker-manager running
    When I run "flapjack-worker-manager start" 
    Then 5 instances of "flapjack-worker" should be running

  Scenario: Running a specified number of workers
    Given the flapjack-worker-manager is on my path
    And there are no instances of flapjack-worker-manager running
    When I run "flapjack-worker-manager start --workers=10" 
    Then 10 instances of "flapjack-worker" should be running

  Scenario: Stopping all workers
    Given there are 5 instances of the flapjack-worker running
    When I run "flapjack-worker-manager stop" 
    Then 0 instances of "flapjack-worker" should be running

