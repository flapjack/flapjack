#!/usr/bin/env ruby

if ENV['COVERAGE']
  require 'simplecov'
  SimpleCov.start do
    add_filter '/features/'
  end
end

ENV["FLAPJACK_ENV"] = 'test'
FLAPJACK_ENV = 'test'

$: << File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'lib'))

require 'pathname'

require 'webmock/cucumber'
WebMock.disable_net_connect!

require 'flapjack/executive'
require 'flapjack/patches'

require 'resque_spec'

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

Mail.defaults do
  delivery_method :test
end

redis_opts = { :db => 14, :driver => :ruby }
redis = ::Redis.new(redis_opts)
redis.flushdb
redis.quit

Before do
  @logger = MockLogger.new
  # Use a separate database whilst testing
  Flapjack::RedisPool.should_receive(:new).and_return( ::Redis.new(redis_opts) )
  @app = Flapjack::Executive.new
  @app.bootstrap(:logger => @logger,
    :config => {'email_queue' => 'email_notifications',
                'sms_queue' => 'sms_notifications'},
    :redis_config => redis_opts)
  @redis = @app.instance_variable_get('@redis')
end

After do
  @redis.flushdb
  @redis.quit
  # Reset the logged messages
  @logger.messages = []
end

Before('@resque') do
  ResqueSpec.reset!
end

Before('@email') do
  Mail::TestMailer.deliveries.clear
end

After('@time') do
  Delorean.back_to_the_present
end

