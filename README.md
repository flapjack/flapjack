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

You'll want to set up a recipients.yaml file so notifications can be sent: 

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

