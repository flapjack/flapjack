series-of-tubes
===============

(have to come up with a better name)

series-of-tubes is highly scalable and distributed monitoring system, analogous
to Nagios. It understands the Nagios plugin format, so you can use your existing 
Nagios checks. It can easily be scaled from 1 server to 1000. 

Currently the code is experimental and proof of concept. Ease-of-use or 
feature completedness is not guaranteed, however it should be *very* performant.


dependencies
============

 - beanstalkd
 - libevent1, libevent-dev

bundled: 

 - beanstalk-client

run `rake deps` to set up bundled deps

running 
=======

start up beanstalkd

populator.rb => puts work items on the 'jobs' tube  
worker.rb => pops work items off the 'jobs' tube, executes job, puts results onto the 'results' tube  
results.rb => processes job results off 'results' tube  
stats.rb => gets stats periodically from beanstalkd tubes  

tenets
======

 - it should be easy to set up
 - it should scale from a single host to multiple
 - writing and sharing checks should be easy and obvious


proposed architecture
=====================

(current implementation vaguely reflects this)

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


- populator determines checks that need to occur, and puts jobs onto 'jobs' tube
  - populator fetches jobs from a database
- workers pop a job off the beanstalk, do job, put result onto 'results' tube, 
  re-add job to 'jobs' tube with a delay. 
- notifier pops off 'results' tube, notifies

