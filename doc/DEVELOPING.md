Developing
----------

You can write your own notifiers and place them in `lib/flapjack/notifiers/`.

Your notifier just needs to implement the `notify` method, and take in a hash:

    class Sms
      def initialize(opts={})
        # you may want to set from address here
        @from = (opts[:from] || "0431 112 233")
      end

      def notify(opts={})
        who = opts[:who]
        result = opts[:result]
        # sms to your hearts content
      end
    end


Testing
-------

Flapjack is, and will continue to be, well tested. Monitoring is like continuous
integration for production apps, so why shouldn't your monitoring system have tests?

Testing is done with rspec, and tests live in `spec/`.

To run the tests, check out the code and run:

    $ rake spec



