Gem::Specification.new do |s|
  s.name = 'flapjack'
  s.version = '0.5.1'
  s.date = '2010-02-28'
  
  s.summary = "a scalable and distributed monitoring system"
  s.description = "Flapjack is highly scalable and distributed monitoring system. It understands the Nagios plugin format, and can easily be scaled from 1 server to 1000."
  
  s.authors = ['Lindsay Holmwood']
  s.email = 'lindsay@holmwood.id.au'
  s.homepage = 'http://flapjack-project.com'
  s.has_rdoc = false

  s.add_dependency('daemons', '= 1.0.10')
  s.add_dependency('beanstalk-client', '= 1.0.2')
  s.add_dependency('log4r', '= 1.1.5')
  s.add_dependency('xmpp4r', '= 0.5')
  s.add_dependency('tmail', '= 1.2.3.1')
  s.add_dependency('yajl-ruby', '= 0.6.4')
  s.add_dependency('sqlite3-ruby', '= 1.2.5')
 
  s.bindir = "bin"
  s.executables = ["flapjack-benchmark", "flapjack-notifier", "flapjack-notifier-manager", "flapjack-stats", "flapjack-worker", "flapjack-worker-manager", "install-flapjack-systemwide" ]
  s.files = ["LICENCE", "README.md", "Rakefile", "TODO.md", "bin/flapjack-benchmark", "bin/flapjack-notifier", "bin/flapjack-notifier-manager", "bin/flapjack-stats", "bin/flapjack-worker", "bin/flapjack-worker-manager", "bin/install-flapjack-systemwide", "doc/CONFIGURING.md", "doc/DEVELOPING.md", "doc/INSTALL.md", "doc/PACKAGING.md", "etc/default/flapjack-notifier", "etc/default/flapjack-workers", "etc/flapjack/flapjack-notifier.conf.example", "etc/flapjack/recipients.conf.example", "etc/init.d/flapjack-notifier", "etc/init.d/flapjack-workers", "features/flapjack-notifier-manager.feature", "features/flapjack-worker-manager.feature", "features/packaging-lintian.feature", "features/persistence/couch.feature", "features/persistence/sqlite3.feature", "features/persistence/steps/couch_steps.rb", "features/persistence/steps/generic_steps.rb", "features/persistence/steps/sqlite3_steps.rb", "features/steps/flapjack-notifier-manager_steps.rb", "features/steps/flapjack-worker-manager_steps.rb", "features/steps/packaging-lintian_steps.rb", "features/support/env.rb", "features/support/silent_system.rb", "flapjack.gemspec", "lib/flapjack/applications/notifier.rb", "lib/flapjack/applications/worker.rb", "lib/flapjack/checks/http_content", "lib/flapjack/checks/ping", "lib/flapjack/cli/notifier.rb", "lib/flapjack/cli/notifier_manager.rb", "lib/flapjack/cli/worker.rb", "lib/flapjack/cli/worker_manager.rb", "lib/flapjack/filters/any_parents_failed.rb", "lib/flapjack/filters/ok.rb", "lib/flapjack/inifile.rb", "lib/flapjack/notifier_engine.rb", "lib/flapjack/notifiers/mailer/init.rb", "lib/flapjack/notifiers/mailer/mailer.rb", "lib/flapjack/notifiers/xmpp/init.rb", "lib/flapjack/notifiers/xmpp/xmpp.rb", "lib/flapjack/patches.rb", "lib/flapjack/persistence/couch.rb", "lib/flapjack/persistence/couch/connection.rb", "lib/flapjack/persistence/couch/couch.rb", "lib/flapjack/persistence/data_mapper.rb", "lib/flapjack/persistence/data_mapper/data_mapper.rb", "lib/flapjack/persistence/data_mapper/models/check.rb", "lib/flapjack/persistence/data_mapper/models/check_template.rb", "lib/flapjack/persistence/data_mapper/models/event.rb", "lib/flapjack/persistence/data_mapper/models/node.rb", "lib/flapjack/persistence/data_mapper/models/related_check.rb", "lib/flapjack/persistence/sqlite3.rb", "lib/flapjack/persistence/sqlite3/sqlite3.rb", "lib/flapjack/transports/beanstalkd.rb", "lib/flapjack/transports/result.rb"]
end


