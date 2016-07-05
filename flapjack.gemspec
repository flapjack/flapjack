# -*- encoding: utf-8 -*-
require File.expand_path('../lib/flapjack/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = [ "Lindsay Holmwood", "Jesse Reynolds", "Ali Graham", "Sarah Kowalik" ]
  gem.email         = "lindsay@holmwood.id.au"
  gem.description   = "Flapjack is a distributed monitoring notification system that provides a scalable method for processing streams of events from Nagios and deciding who should be notified"
  gem.summary       = "Intelligent, scalable, distributed monitoring notification system."
  gem.homepage      = "http://flapjack.io/"
  gem.license       = 'MIT'

  # see http://yehudakatz.com/2010/12/16/clarifying-the-roles-of-the-gemspec-and-gemfile/
  # following a middle road here, not shipping it with the gem :)
  gem.files         = `git ls-files`.split($\) - ['Gemfile.lock']
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "flapjack"
  gem.require_paths = ["lib"]
  gem.version       = Flapjack::VERSION

  gem.add_dependency 'dante', '= 0.2.0'
  gem.add_dependency 'oj', '>= 2.9.0'
  gem.add_dependency 'eventmachine', '~> 1.0.0'
  gem.add_dependency 'redis', '~> 3.0.6'
  gem.add_dependency 'hiredis'
  gem.add_dependency 'em-hiredis'
  gem.add_dependency 'em-synchrony', '~> 1.0.2'
  gem.add_dependency 'em-http-request'
  gem.add_dependency 'sinatra'
  gem.add_dependency 'rack-fiber_pool'
  gem.add_dependency 'thin', '~> 1.6.1'
  gem.add_dependency 'mail'
  gem.add_dependency 'blather', '~> 0.8.3'
  gem.add_dependency 'chronic'
  gem.add_dependency 'chronic_duration'
  gem.add_dependency 'terminal-table'
  gem.add_dependency 'activesupport'
  gem.add_dependency 'ice_cube', '>= 0.14.0'
  gem.add_dependency 'tzinfo'
  gem.add_dependency 'tzinfo-data'
  gem.add_dependency 'rbtrace'
  gem.add_dependency 'rake'
  gem.add_dependency 'gli', '= 2.12.0'
  gem.add_dependency 'nokogiri', '= 1.6.2.1'
  gem.add_dependency 'nexmo', '= 2.0.0'
  gem.add_dependency 'hipchat'
end
