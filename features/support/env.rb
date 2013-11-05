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
  SimpleCov.at_exit do
    Oj.default_options = { :mode => :compat }
    SimpleCov.result.format!
  end
end

@debug = false

ENV["FLAPJACK_ENV"] = 'test'
FLAPJACK_ENV = 'test'

$: << File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'lib'))

require 'pathname'

require 'webmock/cucumber'
WebMock.disable_net_connect!

require 'oj'
Oj.mimic_JSON
Oj.default_options = { :indent => 0, :mode => :strict }
require 'active_support/json'

require 'flapjack/notifier'
require 'flapjack/processor'
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
    local counter = 0

    for i,k in ipairs(keys) do
      local key_ttl = redis.call('ttl', k)

      -- key does not have timeout if < 0
      if ( (key_ttl >= 0) and ((current_time + key_ttl) <= expire_as_if_at) ) then
        redis.call('del', k)
        counter = counter + 1
      end
    end
    return counter
EXPIRE_AS_IF_AT

  def self.before_all(options = {})
    redis = options[:redis]
    @expire_as_if_at_sha = redis.script(:load, ExpireAsIfAtScript)
  end

  def self.before_each(options = {})
    @redis = options[:redis]
  end

  def self.time_travel_to(dest_time)
    #puts "travelling to #{Time.now.in_time_zone}, real time is #{Time.now_without_delorean.in_time_zone}"
    old_maybe_fake_time = Time.now.in_time_zone

    Delorean.time_travel_to(dest_time)
    #puts "travelled to #{Time.now.in_time_zone}, real time is #{Time.now_without_delorean.in_time_zone}"
    return if dest_time < old_maybe_fake_time

    # dumps the first offset -- we're not interested in time difference from
    # real, only with context to the fake frame of reference...
    # This may mean all scenarios using this code should have an initial
    #    Given it is *datetime*
    # step
    offsets = Delorean.send(:time_travel_offsets).dup
    offsets.shift
    delta = -offsets.inject(0){ |sum, val| sum + val }.floor

    real_time = Time.now_without_delorean.to_i
    #puts "delta #{delta}, expire before real time #{Time.at(real_time + delta)}"

    result = @redis.evalsha(@expire_as_if_at_sha, ['*'],
               [real_time, real_time + delta])
    #puts "Expired #{result} key#{(result == 1) ? '' : 's'}"
  end

end

redis_opts = { :db => 14, :driver => :ruby }
redis = ::Redis.new(redis_opts)
redis.flushdb
RedisDelorean.before_all(:redis => redis)
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
end

After do
  @logger.messages = []
end


Before('@processor') do
  @processor = Flapjack::Processor.new(:logger => @logger,
    :redis_config => redis_opts, :config => {})
  @redis = @processor.instance_variable_get('@redis')
end

After('@processor') do
  @redis.flushdb
  @redis.quit
end

Before('@notifier') do
  @notifier  = Flapjack::Notifier.new(:logger => @logger,
    :redis_config => redis_opts,
    :config => {'email_queue' => 'email_notifications',
                'sms_queue' => 'sms_notifications',
                'default_contact_timezone' => 'America/New_York'})
  @notifier_redis = @notifier.instance_variable_get('@redis')
end

After('@notifier') do
  @notifier_redis.flushdb
  @notifier_redis.quit
end

Before('@resque') do
  ResqueSpec.reset!
  @queues = {:email => 'email_queue'}
end

Before('@time') do
  RedisDelorean.before_each(:redis => @redis)
end

After('@time') do
  Delorean.back_to_the_present
end

After('@process') do
  ['tmp/cucumber_cli/flapjack_cfg.yaml',
   'tmp/cucumber_cli/flapjack_cfg.yaml.bak',
   'tmp/cucumber_cli/flapjack_cfg_d.yaml',
   'tmp/cucumber_cli/flapjack_d.log',
   'tmp/cucumber_cli/flapjack_d.pid',
   'tmp/cucumber_cli/nagios_perfdata.fifo',
   'tmp/cucumber_cli/flapjack-nagios-receiver_d.pid',
   'tmp/cucumber_cli/flapjack-nagios-receiver_d.log',
   'tmp/cucumber_cli/flapjack-nagios-receiver_d.yaml',
   'tmp/cucumber_cli/flapjack-nagios-receiver.yaml',
   'tmp/cucumber_cli/flapper_d.pid',
   'tmp/cucumber_cli/flapper_d.log',
   'tmp/cucumber_cli/flapjack-populator.yaml',
   'tmp/cucumber_cli/flapjack-populator-contacts.json',
  ].each do |file|
    next unless File.exists?(file)
    File.unlink(file)
  end
end


