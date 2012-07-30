Flapjack
========

Flapjack is highly scalable and distributed monitoring system.

It understands the Nagios plugin format, and can easily be scaled
from 1 server to 1000.

Flapjack's current focus is on providing a scalable method for dealing with events representing changes in system state (OK -> WARNING -> CRITICAL transitions) and alerting appropriate people as necessary.

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
  * `flapjack-executive` => gets results, works out when and who to notify, sets downtime etc
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

Event-Processing
================

Here's some notes on the event-processing branch, which is at "development of a working prototype".

The idea with this branch is to use Nagios as the check execution engine, and use its 'perfdata' output as an event channel into flapjack-executive which then decides when and who to notifify about problems, recoveries, acknowledgements etc.

Dependencies
------------

Apart from gems:
- Redis

Nagios config
-------------

You need a Nagios prior to version 3.3 as this breaks perfdata output for checks which don't generate performance data (stuff after a | in the check output). I'm using version 3.2.3 with success.

nagios.cfg config file changes:

```
# modified lines:
enable_notifications=0
host_perfdata_file=/usr/local/var/lib/nagios/perfdata_services.fifo
service_perfdata_file=/usr/local/var/lib/nagios/perfdata_services.fifo
host_perfdata_file_template=[HOSTPERFDATA]\t$TIMET$\t$HOSTNAME$\tHOST\t$HOSTSTATE$\t$HOSTEXECUTIONTIME$\t$HOSTLATENCY$\t$HOSTOUTPUT$\t$HOSTPERFDATA$
service_perfdata_file_template=[SERVICEPERFDATA]\t$TIMET$\t$HOSTNAME$\t$SERVICEDESC$\t$SERVICESTATE$\t$SERVICEEXECUTIONTIME$\t$SERVICELATENCY$\t$SERVICEOUTPUT$\t$SERVICEPERFDATA$
host_perfdata_file_mode=p
service_perfdata_file_mode=p
```

All hosts and services (or templates that they use) will need to have process_perf_data enabled on them. (This is a real misnomer, it doesn't mean the performance data will be processed, just that it will be fed to the perfdata output channel, a named pipe in our case.)

Create the named pipe if it doesn't already exist:

    mkfifo -m 0666 /usr/local/var/lib/nagios/perfdata_services.fifo

flapjack-nagios-receiver
This process needs to be started with the nagios perfdata named pipe attached to its STDIN like so:

    be bin/flapjack-nagios-receiver < /usr/local/var/lib/nagios/perfdata_services.fifo

Now as nagios feeds check execution results into the perfdata named pipe, flapjack-nagios-receiver will convert them to JSON encoded ruby objects and insert them into the *events* list in redis.

importing contacts and entities
-------------------------------

The `flapjack-populator` script provides a mechanism for importing contacts and entities from custcare extract files in JSON format.

    be bin/flapjack-populator import-contacts --from=tmp/dummy_contacts.json
    be bin/flapjack-populator import-entities --from=tmp/dummy_entities.json

In lieu of actual documentation of the formats (TODO) there are example files, and example ruby code which generated them, in the tmp directory.

flapjack-executive
------------------

Start flapjack-executive up as follows. This will process events in the 'events' redis list. It a blocking read on redis so new events are picked off the events list and processed as soon as they created.

    be bin/flapjack-executive

When flapjack-executive decides somebody ought to be notified (for a problem, recovery, or acknowledgement or what-have-you) it looks up contact information and then creates a notification job on one of the notification queues (eg sms_notifications) in rescue.

Resque Workers
--------------

We're using [Resque](https://github.com/defunkt/resque) to queue notifications generated by flapjack-executive. The queues are named as follows:
- email_notifications
- sms_notifications

There'll be more of these as we add more notification mediums. One resque worker that processes both queues (but prioritises SMS above email) can be started as follows:

    QUEUE=sms_notifications,email_notifications VERBOSE=1 be rake resque:work

resque sets the command name so grep'ing ps output for `rake` or `ruby` will NOT find resque processes. Search instead for `resque`. (and remember the 'q').

To background it you can add `BACKGROUND=yes`. Excellent documentation is available in [Resque's README](https://github.com/defunkt/resque/blob/master/README.markdown)


