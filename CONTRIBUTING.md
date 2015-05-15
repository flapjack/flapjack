#Contributing to ![Flapjack](http://flapjack.io/images/flapjack-2013-notext-transparent-50-50.png "Flapjack") Flapjack

[![Build Status](https://travis-ci.org/flapjack/flapjack.png)](https://travis-ci.org/flapjack/flapjack)

Please see the [Contributing to Flapjack](http://flapjack.io/docs/1.0/development/DEVELOPING) section of the Flapjack wiki.

> Flapjack is, and will continue to be, well tested. Monitoring is like continuous integration for production apps, so why shouldn't your monitoring system have tests?

## Quick Start

1. clone the repo

        git clone https://github.com/flapjack/flapjack.git

2. install development dependencies with bundler:

        cd flapjack
        gem install bundler
        bundle install

3. install redis
4. run unit tests

        rake spec

5. run [pact](https://github.com/realestate-com-au/pact) tests

        rake pact:verify

6. run integration tests

        rake features

7. code coverage for tests

        COVERAGE=x rake spec
        COVERAGE=x rake pact:verify
        COVERAGE=x rake features

7. make changes with tests, send a [pull request](https://help.github.com/articles/creating-a-pull-request), share love!
