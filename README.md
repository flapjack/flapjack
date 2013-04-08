# Flapjack

[![Travis CI Status][id_travis_img]][id_travis_link]

[id_travis_link]: https://secure.travis-ci.org/#!/flpjck/flapjack
[id_travis_img]: https://secure.travis-ci.org/flpjck/flapjack.png

Flapjack is a highly scalable and distributed monitoring notification system.

Flapjack provides a scalable method for dealing with events representing changes in system state (OK -> WARNING -> CRITICAL transitions) and alerting appropriate people as necessary.

At its core, Flapjack processes events received from external check execution engines, such as Nagios. Nagios provides a 'perfdata' event output channel, which writes to a named pipe. `flapjack-nagios-receiver` then reads from this named pipe, converts each line to JSON and adds them to the events queue.

Flapjack's `executive` component picks up the events and processes them -- deciding when and who to notifify about problems, recoveries, acknowledgements, etc.

Additional check engines can be supported by adding additional receiver processes similar to the nagios receiver.


## Using Flapjack

### Quickstart

TODO numbered list for simplest possible Flapjack run.

For more information, including full specification of the configuration file and the data import formats, please refer to the [Flapjack Wiki](https://github.com/flpjck/flapjack/wiki/USING).

## Developing Flapjack

Information on developing more Flapjack components or contributing to core Flapjack development can be found in the [Flapjack Wiki](https://github.com/flpjck/flapjack/wiki/DEVELOPING).

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


