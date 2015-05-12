source 'https://rubygems.org'

gemspec :name => 'flapjack'

gem 'flapjack-diner', :github => 'flapjack/flapjack-diner', :branch => 'v2_pre'
gem 'zermelo', :github => 'flapjack/zermelo', :branch => '16_zset_indices'

group :development do
  gem 'ruby-prof'
end

group :test do
  gem 'rspec'
  gem 'cucumber', '>= 2.0.0.rc.4'
  gem 'delorean'
  gem 'rack-test'
  gem 'json_spec'
  gem 'webmock'
  gem 'pact'
  gem 'simplecov', :require => false
end
