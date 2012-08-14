if ENV['COVERAGE']
  require 'simplecov'

  SimpleCov.start do
    add_filter '/features/'
    add_filter '/spec/'

    add_group 'Libraries', 'lib'
  end
end

ENV["FLAPJACK_ENV"] = 'test'
require 'bundler'
Bundler.require(:default, :test)

$:.unshift(File.dirname(__FILE__) + '/../lib')

# Requires supporting files with custom matchers and macros, etc,
# in ./support/ and its subdirectories.
Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each {|f| require f}

RSpec.configure do |config|
  # if tests are marked with :focus, run only those, otherwise run all
  config.filter_run :focus => true
  config.run_all_when_everything_filtered = true
end