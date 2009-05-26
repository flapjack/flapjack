Flapjack
========

Flapjack is highly scalable and distributed monitoring system. It understands 
the Nagios plugin format, and can easily be scaled from 1 server to 1000. 



Setup (Ubuntu Hardy)
--------------------

Add the following line to `/etc/apt/sources.list`

    deb http://ppa.launchpad.net/auxesis/ppa/ubuntu hardy main

Install beanstalkd:

    sudo apt-get install beanstalkd

Set `ENABLED=1` in `/etc/default/beanstalkd`.

Start beanstalkd: 

    sudo /etc/init.d/beanstalkd start


Install flapjack:

    sudo gem install flapjack


Setup (everyone else)
---------------------

Install the following software through your package manager or from source: 

 - beanstalkd (from http://xph.us/software/beanstalkd/)
 - libevent (from http://monkey.org/~provos/libevent/)

Run `rake deps` to set up bundled dependencies.




Running 
-------

Start up beanstalkd

`populator.rb` => puts work items on the `jobs` tube  
`worker.rb` => pops work items off the `jobs` tube, executes job, puts results onto the `results` tube  
`notifier.rb` => notifies peopled based on results of checks on the `results` tube  
`stats.rb` => gets stats periodically from beanstalkd tubes (useful for benchmarks)

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

