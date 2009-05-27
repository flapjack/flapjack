Flapjack
========

Flapjack is highly scalable and distributed monitoring system. 

It understands the Nagios plugin format, and can easily be scaled 
from 1 server to 1000. 



Setup dependencies (Ubuntu Hardy)
---------------------------------

Add the following lines to `/etc/apt/sources.list`

    deb http://ppa.launchpad.net/ubuntu-ruby-backports/ubuntu hardy main
    deb http://ppa.launchpad.net/auxesis/ppa/ubuntu hardy main

Add GPG keys for the repos: 

    sudo apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 288BA53BCB7DA731

Update your package list:

    sudo aptitude update 

Install rubygems + beanstalkd:

    sudo apt-get install rubygems beanstalkd

Set `ENABLED=1` in `/etc/default/beanstalkd`.

Start beanstalkd: 

    sudo /etc/init.d/beanstalkd start


Setup dependencies (everyone else)
----------------------------------

Install the following software through your package manager or from source: 

 - beanstalkd (from http://xph.us/software/beanstalkd/)
 - libevent (from http://monkey.org/~provos/libevent/)


Installation
------------

From the checked out code, build + install the gem: 

    rake build
    sudo gem install pkg/flapjack-<latest>.gem

Then run the magic configuration script to set up init scripts: 

    sudo install-flapjack-systemwide

The script will prompt you if it wants to do anything destructive. 


Running 
-------

Make sure beanstalkd is running.

You'll want to set up `/etc/flapjack/recipients.yaml` so notifications can be sent via 
`flapjack-notifier`: 

    - :name: Jane Doe
      :email: "jane@doe.com"
      :phone: "+61 444 222 111"
      :pager: "61444222111"
      :jid: "jane@doe.com"

Start up a cluster of workers: 

    flapjack-worker-manager start

This will spin up 5 workers in the background. You can specify how many workers 
to start: 

    flapjack-worker-manager start --workers=10

Each of the `flapjack-worker`s will output to syslog (check in /var/log/messages).

Start up the notifier: 

    flapjack-notifier --recipients path/to/recipients.yaml

Currently there are email and XMPP notifiers. 

You'll want to get a copy of (http://github.com/auxesis/flapjack-admin/)[flapjack-admin]
to set up some checks, then run its' populator to get them into Flapjack. 

What things do 
--------------

  * `flapjack-worker` => executes checks, reports results  
  * `flapjack-worker-manager` => starts/stops a cluster of `flapjack-worker`
  * `flapjack-notifier` => gets results, notifies people if necessary  
  * `flapjack-stats` => gets stats from beanstalkd tubes (useful for benchmarks + performance analysis)  


init scripts
------------

You can use the provided init scripts to start Flapjack on boot. 

To start: 

    /etc/init.d/flapjack-workers start
    /etc/init.d/flapjack-notifier start

To set Flapjack to start on boot (Ubuntu): 

    sudo update-rc.d flapjack-workers defaults
    sudo update-rc.d flapjack-notifier defaults

Config for the init scripts can be found in `/etc/defaults`.



Developing
----------

You can write your own notifiers and place them in `lib/flapjack/notifiers/`.

Your notifier just needs to implement the `notify` method, and take in a hash:

    class Sms
      def initialize(opts={})
        # you may want to set from address here
      end

      def notify(opts={})
        who = opts[:who]
        result = opts[:result]
        # sms to your hearts content
      end
    end


Testing
-------

Tests are in `spec/`.

To run tests:

    $ rake spec


Architecture
------------

           -------------------
           | web interface / |
           | dsl / flat file |
           -------------------
          /
          |
          |
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


