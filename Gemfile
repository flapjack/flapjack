source 'https://rubygems.org'

gemspec :name => 'flapjack'

gem 'sandstorm', :github => 'flapjack/sandstorm', :branch => 'master'

group :development do
  gem 'ruby-prof'
end

group :test do
  gem 'rspec', '~> 3.0.0.rc1'
  gem 'cucumber'
  gem 'delorean'
  gem 'rack-test'
  gem 'webmock'
  gem 'fuubar', :github => 'eagletmt/fuubar', :branch => 'rspec-300-rc1'
  gem 'simplecov', :require => false
  gem 'debugger-ruby_core_source', '>= 1.3.5' # required for perftools
  gem 'perftools.rb'
end
