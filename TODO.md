
 * setup wiki.flapjack-project.com
 * document new config structure

 * release Flapjack as a distribution-consumable tarball
 * automate building of release tarball that optionally pulls in dependencies
 * add lintian-like checks for verifying packagability (see http://pkg-ruby-extras.alioth.debian.org/upstream-devs.html)
 
 * write packaging guide
 * write installation guide

 * build config file/cli options proxy
 * sandbox flapjack-worker
 * build easily runnable benchmarks for flapjack-{worker,notifier}
 * refactor couchdb backend to be less bongtastic

 * make notification/escalation logic pluggable

 * write puppet manifests
 * provide common interface for loading checks into beanstalk (extract from populator)
 * start side project to have admin interface back onto couchdb
 
 * write zeroconf/avahi notifier
 * write growl notifier
 * write sms notifier
 * allow customisation of notifier messages (body, header)

 * http://www.kitchensoap.com/2009/10/05/meanwhile-more-meta-metrics/

 * write beanstalkd.yreserve to simplify code
 * write beanstalkd.jput, beanstalkd.jreserve for native json api
 
 * add support to worker and notifier for multiple beanstalkds

 * write check generator
   * include a collection of common functions 
     (logging to rrd, retreiving values, executing check)
 * patch beanstalk-client to recognise DRAINING status 



