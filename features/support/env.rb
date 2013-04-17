#!/usr/bin/env ruby
#
require 'delorean'
require 'chronic'
require 'active_support/time'
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

class RedisDelorean

  ExpireAsIfAtScript = <<EXPIRE_AS_IF_AT
    local keys = redis.call('keys', KEYS[1])
    local current_time = tonumber(ARGV[1])
    local expire_as_if_at = tonumber(ARGV[2])

    for i,k in ipairs(keys) do
      local key_ttl = redis.call('ttl', k)

      -- key does not have timeout if < 0
      if ( (key_ttl >= 0) and ((current_time + key_ttl) < expire_as_if_at) ) then
        redis.call('del', k)
      end
    end
EXPIRE_AS_IF_AT

  def self.setup(options = {})
    @redis = options[:redis]
    @expire_as_if_at_sha = @redis.script(:load, ExpireAsIfAtScript)
  end

  def self.time_travel_to(dest_time)
    Delorean.time_travel_to(dest_time)
    @redis.evalsha(@expire_as_if_at_sha, ['*'],
      [Time.now_without_delorean, dest_time])
  end

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
                'sms_queue' => 'sms_notifications',
                'default_contact_timezone' => 'America/New_York'},
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

Before('@time') do
  RedisDelorean.setup(:redis => @redis)
end

After('@time') do
  Delorean.back_to_the_present
end

