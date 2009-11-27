Feature: flapjack-notifier-manager
  So people can be notified when things break
  A notifier must be started
  Through an easy to use command line tool

  Scenario: Starting the notifier
    Given the flapjack-notifier-manager is on my path
    And the "/var/run/flapjack" directory exists and is writable
    And beanstalkd is running on localhost
    And there are no instances of flapjack-notifier running
    When I run "flapjack-notifier-manager start --recipients spec/configs/recipients.ini --config spec/configs/flapjack-notifier.ini" 
    Then 1 instances of "flapjack-notifier" should be running

  Scenario: Stopping the notifier
    Given there is an instance of the flapjack-notifier running
    And beanstalkd is running on localhost
    When I run "flapjack-notifier-manager stop" 
    Then 0 instances of "flapjack-notifier" should be running

