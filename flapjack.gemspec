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
  s.executables = ["flapjack-notifier", "flapjack-notifier-manager", "flapjack-stats", "flapjack-worker", "flapjack-worker-manager", "install-flapjack-systemwide", "flapjack-benchmark"]
  s.files = ["LICENCE", "README.md", "Rakefile", "TODO.md", "bin/flapjack-notifier", "bin/flapjack-notifier-manager", "bin/flapjack-stats", "bin/flapjack-worker", "bin/flapjack-worker-manager", "bin/install-flapjack-systemwide", "doc/CONFIGURING.md", "doc/DEVELOPING.md", "doc/INSTALL.md", "etc/default/flapjack-notifier", "etc/default/flapjack-workers", "etc/flapjack/flapjack-notifier.yaml.example", "etc/flapjack/recipients.yaml.example", "etc/init.d/flapjack-notifier", "etc/init.d/flapjack-workers", "flapjack.gemspec", "lib/flapjack/checks/http_content", "lib/flapjack/cli/notifier.rb", "lib/flapjack/cli/notifier_manager.rb", "lib/flapjack/cli/worker.rb", "lib/flapjack/cli/worker_manager.rb", "lib/flapjack/database.rb", "lib/flapjack/models/check.rb", "lib/flapjack/models/check_template.rb", "lib/flapjack/models/node.rb", "lib/flapjack/models/related_check.rb", "lib/flapjack/notifier.rb", "lib/flapjack/notifiers/mailer/init.rb", "lib/flapjack/notifiers/mailer/mailer.rb", "lib/flapjack/notifiers/xmpp/init.rb", "lib/flapjack/notifiers/xmpp/xmpp.rb", "lib/flapjack/patches.rb", "lib/flapjack/result.rb"]
end


