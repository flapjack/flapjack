Flapjack
========

Flapjack is a highly scalable and distributed monitoring notification system.

Flapjack provides a scalable method for dealing with events representing changes in system state (OK -> WARNING -> CRITICAL transitions) and alerting appropriate people as necessary.

At its core, flapjack process events received from external check execution engines, such as Nagios. Nagios provides a 'perfdata' event output channel, which writes to a named pipe. `flapjack-nagios-receiver` then reads from this named pipe, converts each line to JSON and adds them to the events queue. `executive` picks up the events and processes them - deciding when and who to notifify about problems, recoveries, acknowledgements etc. Additional check engines can be supported by adding additional receiver processes similar to the nagios receiver.


What things do
--------------

Executables:

  * `flapjack` => starts multiple components ('pikelets') within the one ruby process as specified in the configuration file.
  * `flapjack-nagios-receiver` => reads nagios check output on standard input and places them on the events queue in redis as JSON blobs. Currently unable to be run in-process with `flapjack`

There are more fun executables in the bin directory.

Pikelets:

  * `executive` => processes events off a queue (a redis list) and decides what actions to take (alert, record state changes, etc)
  * `email_notifier` => generates email notifications (resque, mail)
  * `sms_notifier` => generates sms notifications (resque)
  * `jabber_gateway` => connects to an XMPP (jabber) server, sends notifications (to rooms and individuals), handles acknowledgements from jabber users and other commands (blather)
  * `web` => web UI (sinatra, thin)
  * `api` => HTTP API server (sinatra, thin)

Pikelets are flapjack components which can be run within the same ruby process, or as separate processes.

The simplest configuration will have one `flapjack` process running executive, web, and some notification gateways, and one `flapjack-nagios-receiver` process receiving events from Nagios and placing them on the events queue for processing by executive.


Developing
----------

Clone the repository:

    git clone https://auxesis@github.com/auxesis/flapjack.git

Install development dependencies:

    gem install bundler
    bundle install

Run the tests:

    cucumber features/
    rspec spec

Testing
-------

Feature tests live in `features/`.

To run feature tests:

    $ cucumber features

There's some rspec unit tests as well, run these like so:

    $ rspec spec

NB, if the cucumber tests fail with a spurious lexing error on line 2 of events.feature, then try this:

    $ cucumber -f fuubar features



Releasing
---------

Gem releases are handled with [Bundler](http://gembundler.com/rubygems.html).

To build the gem, run:

    gem build flapjack.gemspec

Configuring
===========

```
cp etc/flapjack-config.yaml.example etc/flapjack-config.yaml
```

Edit the configuration to suit (redis connection, smtp server, jabber server, sms gateway, etc)

The default FLAPJACK_ENV is "development" if there is no environment variable set.

Nagios config
-------------

You need a Nagios prior to version 3.3 as this breaks perfdata output for checks which don't generate performance data (stuff after a | in the check output). We are developing and running against Nagios version 3.2.3 with success.

nagios.cfg config file changes:

```
# modified lines:
enable_notifications=0
host_perfdata_file=/var/cache/nagios3/event_stream.fifo
service_perfdata_file=/var/cache/nagios3/event_stream.fifo
host_perfdata_file_template=[HOSTPERFDATA]\t$TIMET$\t$HOSTNAME$\tHOST\t$HOSTSTATE$\t$HOSTEXECUTIONTIME$\t$HOSTLATENCY$\t$HOSTOUTPUT$\t$HOSTPERFDATA$
service_perfdata_file_template=[SERVICEPERFDATA]\t$TIMET$\t$HOSTNAME$\t$SERVICEDESC$\t$SERVICESTATE$\t$SERVICEEXECUTIONTIME$\t$SERVICELATENCY$\t$SERVICEOUTPUT$\t$SERVICEPERFDATA$
host_perfdata_file_mode=p
service_perfdata_file_mode=p
```

What we're doing here is telling Nagios to generate a line of output for every host and service check into a named pipe. The template lines must be as above so that `flapjack-nagios-receiver` knows what to expect.

All hosts and services (or templates that they use) will need to have process_perf_data enabled on them. (This is a real misnomer, it doesn't mean the performance data will be processed, just that it will be fed to the perfdata output channel, a named pipe in our case.)

Create the named pipe if it doesn't already exist:

    mkfifo -m 0666 /var/cache/nagios3/event_stream.fifo


Running
=======

    bin/flapjack [options]

    $ flapjack --help
    Usage: flapjack [options]
        -c, --config [PATH]              PATH to the config file to use
        -d, --[no-]daemonize             Daemonize?

The command line option for daemonize overrides whatever is set in the config file.

flapjack-nagios-receiver
------------------------

This process needs to be started with the nagios perfdata named pipe attached to its STDIN like so:

    bin/flapjack-nagios-receiver < /var/cache/nagios3/event_stream.fifo

Now as nagios feeds check execution results into the perfdata named pipe, flapjack-nagios-receiver will convert them to JSON encoded ruby objects and insert them into the *events* queue.

Importing contacts and entities
-------------------------------

The `flapjack-populator` script provides a mechanism for importing contacts and entities from JSON formatted import files.

    bin/flapjack-populator import-contacts --from=tmp/dummy_contacts.json
    bin/flapjack-populator import-entities --from=tmp/dummy_entities.json

TODO: convert the format documentation into markdown and include in the project

In lieu of actual documentation of the formats there are example files, and example ruby code which generated them, in the tmp directory.

executive
---------

Flapjack executive processes events from the 'events' list in redis. It does a blocking read on redis so new events are picked off the events list and processed as soon as they created.

When executive decides somebody ought to be notified (for a problem, recovery, or acknowledgement or what-have-you) it looks up contact information and then creates a notification job on one of the notification queues (eg sms_notifications) in rescue, or via the jabber_notifications redis list which is processed by the jabber_gateway.

Resque Workers
--------------

We're using [Resque](https://github.com/defunkt/resque) to queue email and sms notifications generated by flapjack-executive. The queues are named as follows:
- email_notifications
- sms_notifications

There'll be more of these as we add more notification mediums.

Note that using the flapjack-config.yaml file you can have flapjack start the resque workers in-process. Or you can run them standalone with the `rake resque:work` command as follows.

One resque worker that processes both queues (but prioritises SMS above email) can be started as follows:

    QUEUE=sms_notifications,email_notifications VERBOSE=1 be rake resque:work

resque sets the command name so grep'ing ps output for `rake` or `ruby` will NOT find resque processes. Search instead for `resque`. (and remember the 'q').

To background it you can add `BACKGROUND=yes`. Excellent documentation is available in [Resque's README](https://github.com/defunkt/resque/blob/master/README.markdown)

Redis Database Instances
------------------------

We use the following redis database numbers by convention:

* 0 => production
* 13 => development
* 14 => testing

Architecture
------------

TODO: insert architecture diagram and notes here

Dependencies
------------

Apart from a bundle of gems (see flapjack.gemspec for runtime gems, and Gemfile for additional gems required for testing):
- Ruby >= 1.9
- Redis >= 2.4.15


