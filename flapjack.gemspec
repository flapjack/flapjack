# -*- encoding: utf-8 -*-
require File.expand_path('../lib/flapjack/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = [ 'Lindsay Holmwood', 'Jesse Reynolds', 'Ali Graham' ]
  gem.email         = 'lindsay@holmwood.id.au'
  gem.description   = 'Flapjack is a distributed monitoring notification system that provides a scalable method for processing streams of events from Nagios and deciding who should be notified'
  gem.summary       = 'Intelligent, scalable, distributed monitoring notification system.'
  gem.homepage      = 'http://flapjack-project.com/'

  # see http://yehudakatz.com/2010/12/16/clarifying-the-roles-of-the-gemspec-and-gemfile/
  # following a middle road here, not shipping it with the gem :)
  gem.files         = `git ls-files`.split($\) - ['Gemfile.lock']
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = 'flapjack'
  gem.require_paths = ['lib']
  gem.version       = Flapjack::VERSION

  gem.add_dependency 'dante'
  gem.add_dependency 'oj'
  gem.add_dependency 'hiredis'
  gem.add_dependency 'redis'
  gem.add_dependency 'sinatra'
  gem.add_dependency 'mail'
  gem.add_dependency 'xmpp4r'
  gem.add_dependency 'chronic'
  gem.add_dependency 'chronic_duration'
  gem.add_dependency 'activesupport', '~> 3.2.13'
  gem.add_dependency 'ice_cube'
  gem.add_dependency 'tzinfo'

  gem.add_development_dependency 'rake'
end
