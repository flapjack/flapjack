# ![Flapjack](https://raw.github.com/flpjck/flapjack/gh-pages/images/flapjack-2013-notext-transparent-50-50.png "Flapjack") Flapjack

[![Build Status](https://travis-ci.org/flpjck/flapjack.png)](https://travis-ci.org/flpjck/flapjack)

[Flapjack](http://flapjack.io/) is a flexible monitoring notification routing system that handles:

* **Alert routing** (determining who should receive alerts based on interest, time of day, scheduled maintenance, etc)
* **Alert summarisation** (with per-user, per media summary thresholds)
* **Your standard operational tasks** (setting scheduled maintenance, acknowledgements, etc)

Flapjack will be immediately useful to you if:

* You want to **identify failures faster** by rolling up your alerts across multiple monitoring systems.
* You monitor infrastructures that have **multiple teams responsible** for keeping them up.
* Your monitoring infrastructure is **multitenant**, and each customer has a **bespoke alerting strategy**.
* You want to dip your toe in the water and try alternative check execution engines like Sensu, Icinga, or cron in parallel to Nagios.

### The technical low-down

Flapjack provides a scalable method for dealing with events representing changes in system state (OK -> WARNING -> CRITICAL transitions) and alerting appropriate people as necessary.

At its core, Flapjack processes events received from external check execution engines, such as Nagios. Nagios provides a 'perfdata' event output channel, which writes to a named pipe. `flapjack-nagios-receiver` then reads from this named pipe, converts each line to JSON and adds them to the events queue.

Flapjack sits downstream of check execution engines (like Nagios, Sensu, Icinga, or cron), processing events to determine: 

 * if a problem has been detected
 * who should know about the problem
 * how they should be told

Additional check engines can be supported by adding additional receiver processes similar to the nagios receiver.

## Installing

**Ubuntu Precise 64 (12.04):**

Add the Flapjack Debian repository to your Apt sources:

``` text
echo 'deb http://packages.flapjack.io/deb precise main' > /tmp/flapjack.list
sudo cp /tmp/flapjack.list /etc/apt/sources.list.d/flapjack.list
sudo apt-get update
```

Install the latest Flapjack package:

``` text
sudo apt-get install flapjack
```

Alternatively, [download the deb](http://packages.flapjack.io/deb/pool/main/f/flapjack/) and install using `sudo dpkg -i <filename>`

The Flapjack package is an [Omnibus](https://github.com/opscode/omnibus-ruby) package and as such contains most dependencies under `/opt/flapjack`, including Redis.

Installing the package will start Redis and Flapjack. You should now be able to access the Flapjack Web UI at:

[http://localhost:3080/](http://localhost:3080)

And consume the REST API at:

[http://localhost:3081/](http://localhost:3081)

N.B. The Redis installed by Flapjack runs on a non-standard port, so it doesn't conflict with other Redis instances you may already have installed.

**Other OSes:**

Currently we only make a package for Ubuntu Precise (amd64). If you feel comfortable getting a ruby 1.9 or 2.0 environment going on your preferred OS, then you can also just install Flapjack from rubygems.org:

```text
gem install flapjack
```

Using a tool like [rbenv](https://github.com/sstephenson/rbenv) or [rvm](https://rvm.io/) is recommended to keep your Ruby applications from intefering with one another.

Alternatively, you can add support for your OS of choice to [omnibus-flapjack](https://github.com/flpjck/omnibus-flapjack) and build a native package. Pull requests welcome, and we'll help you make this happen!

## Configuring

Have a look at the default config file and modify things as required. See the [Configuring Components](https://github.com/flpjck/flapjack/wiki/USING#wiki-configuring_components) section on the wiki for more details.

``` bash
# hack the config
sudo vi /etc/flapjack/flapjack_config.yaml

# reload the config
sudo /etc/init.d/flapjack reload
```

## Running

**Ubuntu Precise 64:**

After installing the Flapjack package, Redis and Flapjack should be automatically started.

First up, start Redis if it's not already started:

``` bash
# status:
sudo /etc/init.d/redis status

# start:
sudo /etc/init.d/redis start
```

Operating Flapjack:

``` bash
# status:
sudo /etc/init.d/flapjack status

# reload:
sudo /etc/init.d/flapjack reload

# restart:
sudo /etc/init.d/flapjack restart

# stop:
sudo /etc/init.d/flapjack stop

# start:
sudo /etc/init.d/flapjack start
```

## Using - Details

For more information, including full specification of the configuration file and the data import formats, please refer to the [USING](https://github.com/flpjck/flapjack/wiki/USING) section of the Flapjack wiki

## Developing Flapjack

Information on developing more Flapjack components or contributing to core Flapjack development can be found in the [DEVELOPING](https://github.com/flpjck/flapjack/wiki/DEVELOPING) section of the Flapjack wiki

## Documentation Submodule

We have the documentation for this project on a github wiki and also referenced as a submodule at /doc in this project. Run the following commands to populate the local doc/ directory:

```
git submodule init
git submodule update
```

If you make changes to the documentation locally, here's how to publish them:

* Checkout master within the doc subdir, otherwise you'll be commiting to no branch, a.k.a. *no man's land*.
* git add, commit and push from inside the doc subdir
* Add, commit and push the doc dir from the root (this updates the pointer in the main git repo to the correct ref in the doc repo, we think...)

## More on the wiki

[The Flapjack wiki](https://github.com/flpjck/flapjack/wiki) has even more goodies:

- [Using Flapjack](https://github.com/flpjck/flapjack/wiki/USING)
- [Developing Flapjack](https://github.com/flpjck/flapjack/wiki/DEVELOPING)
- [Redis Data Structure](https://github.com/flpjck/flapjack/wiki/DATA_STRUCTURES)
- [API](https://github.com/flpjck/flapjack/wiki/API)
- [Importing](https://github.com/flpjck/flapjack/wiki/IMPORTING)
- [Debugging Flapjack](https://github.com/flpjck/flapjack/wiki/DEBUGGING)
- [Flapjack Glossary](https://github.com/flpjck/flapjack/wiki/GLOSSARY)
- [Releasing](https://github.com/flpjck/flapjack/wiki/Releasing)
- [Promoting](https://github.com/flpjck/flapjack/wiki/Promoting)


