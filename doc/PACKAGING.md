Debian / Ubuntu
===============

Packaged dependencies: 

 * libdaemons-ruby 
 * liblog4r-ruby
 * libxmpp4r-ruby
 * libtmail-ruby 

Unpackaged dependencies: 

 * beanstalkd-client (libbeanstalkd-ruby)
 * dm-core 
 * dm-timestamps
 * dm-types
 * dm-validations
 * data_objects
 * do_sqlite3
 * do_mysql

The unpackaged dependencies need to be packaged to make Flapjack packagable. 

Current development efforts are working towards abstracting the 
DataMapper/DataObjects dependency so packaging isn't a complete travesty.
