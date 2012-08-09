#!/usr/bin/env ruby

source :rubygems

gem 'daemons'
gem 'beanstalk-client'
gem 'log4r'
gem 'yajl-ruby', :require => 'yajl'
gem 'redis'
gem 'resque'
gem 'mail'
gem 'haml' # moved from web as required in mailer as well
gem 'actionmailer'
gem 'thin'

# TODO split out some of the above gems to separate groups (e.g. mail), only
# require those groups in the parts that need them

group :development do
  gem 'jeweler'
  gem 'shotgun'
end

group :web do
  gem 'sinatra'
  gem 'tilt'
  gem 'warden'
  gem 'sinatra_more'
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
