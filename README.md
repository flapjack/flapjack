# Flapjack

[![Travis CI Status][id_travis_img]][id_travis_link]

[id_travis_link]: https://secure.travis-ci.org/#!/flpjck/flapjack
[id_travis_img]: https://secure.travis-ci.org/flpjck/flapjack.png

[flapjack-project.com](http://flapjack-project.com/)

Flapjack is a highly scalable and distributed monitoring notification system.

Flapjack provides a scalable method for dealing with events representing changes in system state (OK -> WARNING -> CRITICAL transitions) and alerting appropriate people as necessary.

At its core, Flapjack processes events received from external check execution engines, such as Nagios. Nagios provides a 'perfdata' event output channel, which writes to a named pipe. `flapjack-nagios-receiver` then reads from this named pipe, converts each line to JSON and adds them to the events queue.

Flapjack's `executive` component picks up the events and processes them -- deciding when and who to notifify about problems, recoveries, acknowledgements, etc.

Additional check engines can be supported by adding additional receiver processes similar to the nagios receiver.


## Using

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


