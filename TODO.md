 * hook notifier into web interface
   * update status of checks - DONE
   * relationships + cascading notifications - DONE
   * simple graphs
   * event/result history
 * build option to specify notifier(s) directory
 * trigger populator from web interface
 * documentation!
   * user
   * developer
   * step-by-step install guide
   * scaling guide
   * integrating with collectd guide
   * writing custom populators guide
 * write puppet manifests
 * package with pallet
 * generate .deb/.rpms
   * build packages for gem dependencies
 * sandbox flapjack-worker
   * provide config option for specifying sandbox dir
 * provide common interface for loading checks into beanstalk
 * write check generator
   * include a collection of common functions 
     (logging to rrd, retreiving values, executing check)
 * write zeroconf/avahi notifier
 * write growl notifier
 * write way to customise notifier messages (email body, xmpp format)
 * write sms notifier
