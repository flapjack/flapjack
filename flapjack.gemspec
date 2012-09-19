# -*- encoding: utf-8 -*-
require File.expand_path('../lib/flapjack/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Lindsay Holmwood"]
  gem.email         = %q{lindsay@holmwood.id.au}
  gem.description   = %q{Flapjack is highly scalable and distributed monitoring system. It understands the Nagios plugin format, and can easily be scaled from 1 server to 1000.}
  gem.summary       = %q{a scalable and distributed monitoring system}
  gem.homepage      = %q{http://flapjack-project.com/}

  # see http://yehudakatz.com/2010/12/16/clarifying-the-roles-of-the-gemspec-and-gemfile/
  # following a middle road here, not shipping it with the gem :)
  gem.files         = `git ls-files`.split($\) - ['Gemfile.lock', 'bin/flapjack-bpimport']
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "flapjack"
  gem.require_paths = ["lib"]
  gem.version       = Flapjack::VERSION

  gem.add_dependency 'daemons'
  gem.add_dependency 'log4r'
  gem.add_dependency 'yajl-ruby'
  gem.add_dependency 'eventmachine', '~> 1.0.0'
  gem.add_dependency 'hiredis'
  gem.add_dependency 'em-synchrony', '~> 1.0.2'
  gem.add_dependency 'em-http-request'
  gem.add_dependency 'redis'
  gem.add_dependency 'em-resque'
  gem.add_dependency 'sinatra'
  gem.add_dependency 'rack-fiber_pool'
  gem.add_dependency 'haml'
  gem.add_dependency 'thin'
  gem.add_dependency 'mail'
  gem.add_dependency 'blather'
  gem.add_dependency 'chronic'
  gem.add_dependency 'chronic_duration'
  gem.add_dependency 'httparty'

  gem.add_development_dependency 'rake'
  gem.add_development_dependency 'colorize'
end
