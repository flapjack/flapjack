#!/usr/bin/env ruby

require 'rubygems'
require 'simplecov'
SimpleCov.start do
  add_filter '/features/'
end
SimpleCov.coverage_dir 'coverage/cucumber'

require 'bundler'
Bundler.setup(:default, :cucumber)

$: << File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'lib'))

require 'pathname'

require 'webmock/cucumber'
WebMock.disable_net_connect!

require 'flapjack/executive'
require 'flapjack/patches'

class MockLogger
  attr_accessor :messages

  def initialize
    @messages = []
  end

  %w(debug info warn error fatal).each do |level|
    class_eval <<-RUBY
      def #{level}(msg)
        @messages << msg
      end
    RUBY
  end
end

Before do
  @logger = MockLogger.new
  # Use a separate database whilst testing
  @app = Flapjack::Executive.new(:redis => { :db => 14 }, :logger => @logger)
  @app.drain_events
  @redis = Flapjack.persistence
end

After do
  # Reset the logged messages
  Flapjack.logger.messages = []
end

Around('@email') do |scenario, block|
  ActionMailer::Base.delivery_method = :test
  ActionMailer::Base.perform_deliveries = true
  ActionMailer::Base.deliveries.clear
  block.call
end

# not sure why this has to be explicitly required -- Bundler should
# be doing this
require 'resque_spec'

Before('@resque') do
  ResqueSpec.reset!
end
