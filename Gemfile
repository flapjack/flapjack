source 'https://rubygems.org'

gemspec :name => 'flapjack'

group :development do
  gem 'ruby-prof'
end

group :test do
  gem 'rspec', '~> 3.0'
  gem 'cucumber', '>= 2.0.0.beta.3'
  gem 'delorean'
  gem 'rack-test'
  gem 'pact'
  gem 'async_rack_test', '>= 0.0.5'
  gem 'resque_spec'
  gem 'webmock'
  gem 'guard'
  gem 'rb-fsevent'
  gem 'guard-rspec'
  gem 'guard-cucumber'
  gem 'fuubar'
  gem 'simplecov', :require => false

  # # Not compiling under 1.9.3-p550 anyway
  # if RUBY_VERSION.split('.')[0] == '1' && RUBY_VERSION.split('.')[1] == '9'
  #   gem 'debugger-ruby_core_source', '>= 1.3.4' # required for perftools.rb
  #   gem 'perftools.rb'
  # end
end
