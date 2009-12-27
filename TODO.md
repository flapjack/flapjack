 * refactor couchdb backend to be less bongtastic
 * write "action" hooks API on notifications

 * write migration tool for sqlite3 => couchdb

 * write persistence backend setup tool (create couchdb/sqlite3 database)

 * add lintian-like checks for verifying packagability (see http://pkg-ruby-extras.alioth.debian.org/upstream-devs.html)
 * sandbox flapjack-worker
 * write beanstalkd.yreserve to simplify code
 * write beanstalkd.jput, beanstalkd.jreserve for native json api

 * build config file/cli options proxy
 * build easily runnable benchmarks for flapjack-{worker,notifier}

 * update installation guide
 * clean up persistence API to be more user friendly

 * write puppet manifests
 * provide common interface for loading checks into beanstalk (extract from populator)
 
 * write zeroconf/avahi notifier
 * write growl notifier
 * write sms notifier
 * allow customisation of notifier messages (body, header)

 * http://www.kitchensoap.com/2009/10/05/meanwhile-more-meta-metrics/

 * add support to worker and notifier for multiple beanstalkds
 * patch beanstalk-client to recognise DRAINING status 

 * write check generator
   * include a collection of common functions 
     (logging to rrd, retreiving values, executing check)


