#!/usr/bin/env ruby

source :rubygems

gem 'daemons'
gem 'beanstalk-client'
gem 'log4r'
gem 'yajl-ruby', :require => 'yajl'

gem 'em-synchrony'
gem 'redis'
gem 'em-resque'

group :development do
  gem 'jeweler'
  gem 'shotgun'
end

group :web do
  gem 'sinatra'
  gem 'tilt'
  gem 'warden'
  gem 'sinatra_more'
  gem 'rack-fiber_pool'
  gem 'haml'  
  gem 'thin'
  # pony is vendored into sinatra_more (?), and requires these
  gem 'mail'
  gem 'actionmailer', :require => 'action_mailer'
end

group :email do
  gem 'haml'
  gem 'mail'
  gem 'actionmailer', :require => 'action_mailer'
end

group :rspec do
  gem 'rspec'
end

group :cucumber do
  gem 'rspec'
  gem 'cucumber'
  gem 'delorean'
  gem 'resque_spec'
  gem 'webmock'
  gem 'simplecov', :require => false
end
