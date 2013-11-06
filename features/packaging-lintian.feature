Feature: Packagability
  To make Flapjack usable to the masses
  It must be easily packagable

  Scenario: No rubygems references
    When I run `grep require lib/* bin/* -R |grep rubygems`
    Then the exit status should not be 0
    And I should see 0 lines of output

  Scenario: A shebang that works everywhere
    When I run `find lib/ -type 'f' -name '*.rb'`
    Then the exit status should be 0
    And every file in the output should start with "#!/usr/bin/env ruby"


