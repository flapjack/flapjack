Flapjack
========

**WARNING: Flapjack is no longer under active development. **

**Feel free to fork it, but I don't have the bandwidth to work on this project any longer. **

Flapjack is highly scalable and distributed monitoring system.

It understands the Nagios plugin format, and can easily be scaled
from 1 server to 1000.


Installation
------------

Installation is currently driven by Puppet. The required Puppet modules to install Flapjack are in `dist/puppet/`.

**WARNING** the Puppet modules are currently Ubuntu specific. If you want to install Flapjack on another platform, you'll have to refactor them. Patches welcome!

To install, copy these modules into your Puppet repository, and apply the `flapjack::worker` + `flapjack::notifier` classes to the machines you wish to run the workers and notifier on respectively.

Once the modules are in place and applied to nodes, do a normal Puppet run.

Most of what's documented below is automated by Puppet, and can be considered a usage guide.

Running
-------

Make sure beanstalkd is running.

You'll want to set up `/etc/flapjack/recipients.conf` so notifications can be sent via
`flapjack-notifier`:

    [John Doe]
      email = johndoe@example.org
      jid = john@example.org
      phone = +61 400 111 222
      pager = 61400111222

    [Jane Doe]
      email = janedoe@example.org
      jid = jane@example.org
      phone = +61 222 333 111
      pager = 61222333111

You also need to set up `/etc/flapjack/notifier.conf`:

    # top level
    [notifier]
      notifier-directories = /usr/lib/flapjack/notifiers/ /path/to/my/notifiers
      notifiers = mailer, xmpp

    # persistence layers
    [persistence]
      backend = data_mapper
      uri = sqlite3:///tmp/flapjack.db

    # message transports
    [transport]
      backend = beanstalkd
      host = localhost
      port = 11300

    # notifiers
    [mailer-notifier]
      from_address = foo@bar.com

    [xmpp-notifier]
      jid = foo@bar.com
      password = barfoo

    # filters
    [filters]
      chain = ok, downtime, any_parents_failed


Start up a cluster of workers:

    flapjack-worker-manager start

This will spin up 5 workers in the background. You can specify how many workers
to start:

    flapjack-worker-manager start --workers=10

Each of the `flapjack-worker`s will output to syslog (check in /var/log/messages).

Start up the notifier:

    flapjack-notifier-manager start --recipients /etc/flapjack/recipients.conf

Currently there are email and XMPP notifiers.

Developing
----------

Clone the repository:

    git clone https://auxesis@github.com/auxesis/flapjack.git

Install development dependencies:

    gem install bundler
    bundle install

Run the tests:

    cucumber features/


What things do
--------------

  * `flapjack-worker` => executes checks, reports results
  * `flapjack-worker-manager` => starts/stops a cluster of `flapjack-worker`
  * `flapjack-notifier` => gets results, notifies people if necessary
  * `flapjack-stats` => gets stats from beanstalkd tubes (useful for benchmarks + performance analysis)
  * `flapjack-benchmark` => benchmarks various persistence/transport backend combinations


Testing
-------

Tests live in `features/`.

To run tests:

    $ rake cucumber


Architecture
------------

    -------------------        -------------------
    | web interface / |        | visualisation / |
    | dsl / flat file |        | reporting       |
    -------------------        -------------------
              |                   |
               \                 /
                \               /
                 ---------------
                 | persistence |
                 ---------------
                        |
          -------------------------------
          |                             |
          |                             |
          |                             |
    -------------                  ------------
    | populator |---          -----| notifier |
    -------------  |          |    ------------
                   |          |
                  --------------
                  | beanstalkd |
                  --------------
                        |
       -----------------------------------
       |                |                |
    ----------      ----------       ----------
    | worker |      | worker |       | worker |
    ----------      ----------       ----------


- populator determines checks that need to occur, and puts checks onto `jobs` tube
  - populator fetches jobs from a database
  - populator can be swapped out to get checks from a dsl or flat files
- workers pop a check off the beanstalk, perform check, put result onto `results` tube,
  re-add check to `jobs` tube with a delay.
- notifier pops results off `results` tube, notifies as necessary

Releasing
---------

Gem releases are handled with [Jeweler](https://github.com/technicalpickles/jeweler).
