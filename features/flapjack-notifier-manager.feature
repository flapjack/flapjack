Feature: flapjack-notifier-manager
  To scale Flapjack easily and efficiently
  A sysadmin
  Must be able to manage clusters of workers

  Scenario: Starting the notifier
    Given the flapjack-notifier-manager is on my path
    And beanstalkd is running on localhost
    And there are no instances of flapjack-notifier running
    When I run "flapjack-notifier-manager start --recipients spec/fixtures/recipients.yaml --config spec/fixtures/flapjack-notifier.yaml" 
    Then 1 instances of "flapjack-notifier" should be running

  Scenario: Stopping the notifier
    Given there is an instance of the flapjack-notifier running
    And beanstalkd is running on localhost
    When I run "flapjack-notifier-manager stop" 
    Then 0 instances of "flapjack-notifier" should be running

