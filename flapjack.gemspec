Gem::Specification.new do |s|
  s.name = 'flapjack'
  s.version = '0.3.8'
  s.date = '2009-05-26'
  
  s.summary = "a scalable and distributed monitoring system"
  s.description = "Flapjack is highly scalable and distributed monitoring system. It understands the Nagios plugin format, and can easily be scaled from 1 server to 1000."
  
  s.authors = ['Lindsay Holmwood']
  s.email = 'lindsay@holmwood.id.au'
  s.homepage = 'http://flapjack-project.com'
  s.has_rdoc = false

  s.add_dependency('daemons', '>= 1.0.10')
  s.add_dependency('beanstalk-client', '>= 1.0.2')
  s.add_dependency('log4r', '>= 1.0.5')
  s.add_dependency('xmpp4r-simple', '>= 0.8.8')
  s.add_dependency('mailfactory', '>= 1.4.0')
 
  s.bindir = "bin"
  s.executables = ["flapjack-notifier", "flapjack-notifier-manager", "flapjack-stats", "flapjack-worker", "flapjack-worker-manager", "install-flapjack-systemwide"]
  s.files = ["README.md", "Rakefile", "TODO.md", "bin/flapjack-notifier", "bin/flapjack-notifier-manager", "bin/flapjack-stats", "bin/flapjack-worker", "bin/flapjack-worker-manager", "bin/install-flapjack-systemwide", "etc/default/flapjack-notifier", "etc/default/flapjack-workers", "etc/flapjack/recipients.yaml", "etc/init.d/flapjack-notifier", "etc/init.d/flapjack-workers", "flapjack.gemspec", "lib/flapjack/cli/notifier.rb", "lib/flapjack/cli/notifier_manager.rb", "lib/flapjack/cli/worker.rb", "lib/flapjack/cli/worker_manager.rb", "lib/flapjack/notifier.rb", "lib/flapjack/notifiers/mailer.rb", "lib/flapjack/notifiers/xmpp.rb", "lib/flapjack/patches.rb", "lib/flapjack/result.rb"]
end


