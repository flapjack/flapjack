#!/usr/bin/env ruby

$: << File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'lib'))

require 'yajl'
require 'beanstalk-client'

#require 'flapjack/inifile'
#require 'flapjack/filters/ok'
#require 'flapjack/filters/any_parents_failed'
#require 'flapjack/notifier_engine'
#require 'flapjack/transports/result'
#require 'flapjack/transports/beanstalkd'
#require 'flapjack/patches'
#require 'flapjack/inifile'
#require 'flapjack/cli/worker_manager'
#require 'flapjack/cli/notifier_manager'
#require 'flapjack/cli/notifier'
#require 'flapjack/cli/worker'
#require 'flapjack/persistence/couch'
#require 'flapjack/persistence/sqlite3'
#require 'flapjack/applications/notifier'
#require 'flapjack/applications/worker'
#require 'flapjack/notifiers/mailer/init'
#require 'flapjack/notifiers/xmpp/init'
