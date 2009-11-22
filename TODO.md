 * create events for failed checks

 * rethink Notifier/NotifierCLI split
   Notifier + NotifierCLI are tightly coupled, which makes it difficult to refactor
   follow Puppet's lead with Puppet::Application (NotifierCLI translates to Flapjack::Notifier::Application)
   implement simple interface application interface: Flapjack::Notifier::Application.run(options)

 * make notification/escalation logic pluggable (to reduce packaging dependencies)

 * release Flapjack as a distribution-consumable tarball
 * automate building of release tarball that optionally pulls in dependencies
 * add lintian-like checks for verifying packagability (see http://pkg-ruby-extras.alioth.debian.org/upstream-devs.html)
 
 * build easily runnable benchmarks for flapjack-{worker,notifier}

 * setup wiki.flapjack-project.com
 * documentation!
   * user
   * developer
   * step-by-step install guide
   * scaling guide
   * integrating with collectd guide
   * writing custom populators guide
 * write puppet manifests
 
 * build option to specify notifier(s) directory
 * sandbox flapjack-worker
   * provide config option for specifying sandbox dir

 * provide common interface for loading checks into beanstalk (extract from populator)
 * make message queueing interface more abstract (support for AMQP/RabbitMQ)
 
 * write zeroconf/avahi notifier
 * write growl notifier
 * write sms notifier
 * write way to customise notifier messages (email body, xmpp format)

 * http://www.kitchensoap.com/2009/10/05/meanwhile-more-meta-metrics/

 * write beanstalkd.yreserve to simplify code
 * write beanstalkd.jput, beanstalkd.jreserve for native json api
 
 * add support to worker and notifier for multiple beanstalkds

 * write check generator
   * include a collection of common functions 
     (logging to rrd, retreiving values, executing check)
 * patch beanstalk-client to recognise DRAINING status 



