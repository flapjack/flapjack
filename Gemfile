source 'https://rubygems.org'

gemspec :name => 'flapjack'

gem 'sandstorm', :github => 'flapjack/sandstorm', :branch => 'master'

group :development do
  gem 'ruby-prof'
end

group :test do
  gem 'rspec'
  gem 'cucumber'
  gem 'delorean'
  gem 'rack-test'
  gem 'webmock'
  gem 'pact'
  gem 'fuubar'
  gem 'simplecov', :require => false

  # # Not compiling at the moment
  # if RUBY_VERSION.split('.')[0] == '1' && RUBY_VERSION.split('.')[1] == '9'
  #   gem 'debugger-ruby_core_source', :github => 'moneill/debugger-ruby_core_source', :branch => '1.9.3-p550_headers' # required for perftools.rb
  #   gem 'perftools.rb'
  # end
end
