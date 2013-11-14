# Flapjack

[![Build Status](https://travis-ci.org/flpjck/flapjack.png)](https://travis-ci.org/flpjck/flapjack)

[flapjack-project.com](http://flapjack-project.com/)

Flapjack is a highly scalable and distributed monitoring notification system.

Flapjack provides a scalable method for dealing with events representing changes in system state (OK -> WARNING -> CRITICAL transitions) and alerting appropriate people as necessary.

At its core, Flapjack processes events received from external check execution engines, such as Nagios. Nagios provides a 'perfdata' event output channel, which writes to a named pipe. `flapjack-nagios-receiver` then reads from this named pipe, converts each line to JSON and adds them to the events queue.

Flapjack picks up the events and processes them -- deciding when and who to notifify about problems, recoveries, acknowledgements, etc.

Additional check engines can be supported by adding additional receiver processes similar to the nagios receiver.

## Installing

**Ubuntu Precise 64 (12.04):**

Add the flapjack deb repository to your apt sources:

```text
echo 'deb http://packages.flapjack.io/deb precise main' > /tmp/flapjack.list
sudo cp /tmp/flapjack.list /etc/apt/sources.list.d/flapjack.list
sudo apt-get update
```

Install the latest flapjack package:

```text
sudo apt-get install flapjack
```

Alternatively, [download the deb](http://packages.flapjack.io/deb/pool/main/f/flapjack/) and install using `sudo dpkg -i <filename>`

The flapjack package is an 'omnibus' package and as such contains most dependencies under /opt/flapjack, including redis.

Installing the package will start redis and flapjack. You should now be able to access the flapjack Web UI at:

[http://localhost:3080/](http://localhost:3080)

And consume the REST API at:

[http://localhost:3081/](http://localhost:3081)

**Other OSes:**

Currently we only make a package for Ubuntu Precise (amd64). If you feel comfortable getting a ruby 1.9 or 2.0 environment going on your preferred OS, then you can also just install flapjack from rubygems.org:

```text
gem install flapjack
```

Using a tool like [rbenv](https://github.com/sstephenson/rbenv) or [rvm](https://rvm.io/) is recommended to keep your ruby applications from intefering with one another.

Alternatively, you can add support for your OS of choice to [omnibus-flapjack](https://github.com/flpjck/omnibus-flapjack) and build a native package. Pull requests welcome!

## Configuring

Have a look at the default config file and modify things as required. See the [Configuring Components](https://github.com/flpjck/flapjack/wiki/USING#wiki-configuring_components) section on the wiki for more details.

```bash
# hack the config
sudo vi /etc/flapjack/flapjack_config.yaml

# reload the config
sudo /etc/init.d/flapjack reload
```

## Running

**Ubuntu Precise 64:**

After installing the flapjack package, redis and flapjack should be automatically started.

First up, start redis if it's not already started:
```bash
# status:
sudo /etc/init.d/redis status

# start:
sudo /etc/init.d/redis start
```

Operating flapjack:
```bash
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

https://github.com/flpjck/flapjack/wiki has even more goodies:

- [Using Flapjack](https://github.com/flpjck/flapjack/wiki/USING)
- [Developing Flapjack](https://github.com/flpjck/flapjack/wiki/DEVELOPING)
- [Redis Data Structure](https://github.com/flpjck/flapjack/wiki/DATA_STRUCTURES)
- [API](https://github.com/flpjck/flapjack/wiki/API)
- [Importing](https://github.com/flpjck/flapjack/wiki/IMPORTING)
- [Debugging Flapjack](https://github.com/flpjck/flapjack/wiki/DEBUGGING)
- [Flapjack Glossary](https://github.com/flpjck/flapjack/wiki/GLOSSARY)


