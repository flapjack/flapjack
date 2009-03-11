Flapjack
========

Flapjack is highly scalable and distributed monitoring system. It understands 
the Nagios plugin format, and can easily be scaled from 1 server to 1000. 

Currently the code is experimental and proof of concept. Ease-of-use or 
feature completedness is not guaranteed, however it should be *very* performant.


Dependencies + Setup
--------------------

 - beanstalkd
 - libevent1, libevent-dev

You can get beanstalkd from: http://xph.us/software/beanstalkd/

Run `rake deps` to set up bundled dependencies.

Running 
-------

Start up beanstalkd

`populator.rb` => puts work items on the `jobs` tube  
`worker.rb` => pops work items off the `jobs` tube, executes job, puts results onto the `results` tube  
`notifier.rb` => notifies peopled based on results of checks on the `results` tube  
`stats.rb` => gets stats periodically from beanstalkd tubes (useful for benchmarks)

Proposed Architecture
---------------------

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


- populator determines checks that need to occur, and puts jobs onto `jobs` tube
  - populator fetches jobs from a database
- workers pop a job off the beanstalk, do job, put result onto `results` tube, 
  re-add job to `jobs` tube with a delay. 
- notifier pops off `results` tube, notifies

