#!/usr/bin/env ruby

$: << File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'lib'))

require 'pathname'
require 'yajl'
require 'beanstalk-client'
require 'daemons'
require 'webmock/cucumber'
require 'flapjack/executive'
require 'flapjack/patches'

WebMock.disable_net_connect!

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
