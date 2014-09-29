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
  gem 'fuubar'
  gem 'simplecov', :require => false

  if RUBY_VERSION.split('.')[0] == '1' && RUBY_VERSION.split('.')[1] == '9'
    gem 'debugger-ruby_core_source', '>= 1.3.4' # required for perftools.rb
    gem 'perftools.rb'
  end
end
