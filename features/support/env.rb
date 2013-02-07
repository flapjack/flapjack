#!/usr/bin/env ruby
#
require 'delorean'
require 'chronic'
require 'active_support/time_with_zone'
require 'ice_cube'
require 'flapjack/data/entity_check'
require 'flapjack/data/event'

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

# poor man's stubbing
class MockEmailer
  include EM::Deferrable
end

redis_opts = { :db => 14, :driver => :ruby }
redis = ::Redis.new(redis_opts)
redis.flushdb
redis.quit

# NB: this seems to execute outside the Before/After hooks
# regardless of placement -- this is what we want, as the
# @redis driver should be initialised in the sync block.
Around do |scenario, blk|
  EM.synchrony do
    blk.call
    EM.stop
  end
end

Before do
  @logger = MockLogger.new
  # Use a separate database whilst testing
  @app = Flapjack::Executive.new(:logger => @logger,
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
  @queues = {:email => 'email_queue'}
end

After('@time') do
  Delorean.back_to_the_present
end

