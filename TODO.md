 * create events for failed checks
 * build option to specify notifier(s) directory
 * documentation!
   * user
   * developer
   * step-by-step install guide
   * scaling guide
   * integrating with collectd guide
   * writing custom populators guide
 * build benchmarks for flapjack-{worker,notifier}
 * write puppet manifests
 * package with pallet
 * generate .deb/.rpms
   * build packages for gem dependencies
 * sandbox flapjack-worker
   * provide config option for specifying sandbox dir
 * provide common interface for loading checks into beanstalk (extract from populator)
 * write check generator
   * include a collection of common functions 
     (logging to rrd, retreiving values, executing check)
 * write zeroconf/avahi notifier
 * write growl notifier
 * write way to customise notifier messages (email body, xmpp format)
 * write sms notifier
 * patch beanstalk-client to recognise DRAINING status 
 * http://www.kitchensoap.com/2009/10/05/meanwhile-more-meta-metrics/
