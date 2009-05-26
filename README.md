Flapjack
========

Flapjack is highly scalable and distributed monitoring system. 

It understands the Nagios plugin format, and can easily be scaled 
from 1 server to 1000. 



Setup dependencies (Ubuntu Hardy)
---------------------------------

Add the following line to `/etc/apt/sources.list`

    deb http://ppa.launchpad.net/auxesis/ppa/ubuntu hardy main

Install beanstalkd:

    sudo apt-get install beanstalkd

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

Install flapjack:

    sudo gem install flapjack



Running 
-------

Make sure beanstalkd is running.

`flapjack-worker` => executes checks, reports results
`flapjack-notifier` => gets results, notifies people if necessary
`flapjack-stats` => gets stats from beanstalkd tubes (useful for benchmarks + performance analysis)

You'll want to set up a `recipients.yaml` file so notifications can be sent: 

    - :name: John Doe
      :email: "john@doe.com"
      :phone: "+61 444 333 222"
      :pager: "61444333222"
      :jid: "john@doe.com"
    - :name: Jane Doe
      :email: "jane@doe.com"
      :phone: "+61 444 222 111"
      :pager: "61444222111"
      :jid: "jane@doe.com"

Currently there are email and XMPP notifiers. 


Developing
----------

You can write your own notifiers and place them in `lib/flapjack/notifiers/`.

Your notifier just needs to implement the `notify!` method, and take in a hash:

    class Sms
      def initialize(opts={})
        # you may want to set from address here
      end

      def notify!(opts={})
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


