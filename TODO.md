 * daemonise notifier - DONE
 * provide config file for notifier
   * specify which notifier plugins to load - DONE
   * specify configuration for plugins (from address/xmmp login) - DONE
 * write init scripts for notifier/worker-manager - DONE
 * hook notifier into web interface
   * update status of checks - DONE
   * relationships + cascading notifications
   * simple graphs
 * package with pallet
 * generate .deb/.rpms
   * build packages for gem dependencies
 * provide common interface for loading checks into beanstalk
 * write check generator
   * include a collection of common functions 
     (logging to rrd, retreiving values, executing check)
 * write zeroconf/avahi notifier
 * write growl notifier
 * write way to customise notifier messages (email body, xmpp format)
 * write sms notifier
