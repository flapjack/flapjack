Feature: Packagability 
  To make Flapjack usable to the masses
  It must be easily packagable

  Scenario: No rubygems references
    Given I am at the project root
    When I run "grep require lib/* bin/* -R |grep rubygems"
    Then I should see 0 lines of output

