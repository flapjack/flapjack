 * daemonise notifier - DONE
 * provide config file for notifier
   * specify which notifier plugins to load
   * specify configuration for plugins (from address/xmmp login)
 * write init scripts for notifier/worker-manager - DONE
 * hook notifier into web interface
   * update status of checks
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
