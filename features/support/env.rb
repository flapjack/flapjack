#!/usr/bin/env ruby

Encoding.default_internal = 'UTF-8'

require 'delorean'
require 'chronic'
require 'active_support/time'
require 'ice_cube'
require 'flapjack/configuration'
require 'flapjack/data/entity_check'
require 'flapjack/data/event'

if ENV['COVERAGE']
  require 'simplecov'
  SimpleCov.start do
    add_filter '/features/'
  end
  SimpleCov.at_exit do
    SimpleCov.result.format!
  end
end

@debug = false

ENV["FLAPJACK_ENV"] = 'test'
FLAPJACK_ENV = 'test'
FLAPJACK_ROOT   = File.join(File.dirname(__FILE__), '..', '..')
FLAPJACK_CONFIG = File.join(FLAPJACK_ROOT, 'etc', 'flapjack_config.yaml')

$: << File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'lib'))

require 'pathname'

require 'webmock/cucumber'
WebMock.disable_net_connect!

require 'flapjack'
require 'flapjack/notifier'
require 'flapjack/processor'
require 'flapjack/patches'

class MockLogger
  attr_accessor :messages

  def initialize
    @messages = []
  end

  %w(debug info warn error fatal).each do |level|
    class_eval <<-RUBY
      def #{level}(msg)
        # puts "#{level}: "+msg
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

  ShiftTTLsScript = <<SHIFT_TTLS
    local keys = redis.call('keys', KEYS[1])
    local ttl_decrease = tonumber(ARGV[1])
    local deleted = 0

    for i,k in ipairs(keys) do
      local key_ttl = redis.call('ttl', k)

      -- key does not have timeout if < 0
      if key_ttl >= 0 then
        local diff = key_ttl - ttl_decrease
        if diff <= 0 then
          redis.call('del', k)
          deleted = deleted + 1
        else
          redis.call('expire', k, diff)
        end
      end
    end
    return deleted
SHIFT_TTLS

  def self.before_all(options = {})
    redis = options[:redis]
    @shift_ttls_sha = redis.script(:load, ShiftTTLsScript)
  end

  def self.before_each(options = {})
    @redis = options[:redis]
  end

  def self.time_travel_to(dest_time)
    old_maybe_fake_time = Time.now.in_time_zone
    Delorean.time_travel_to(dest_time)
    # puts "real time is #{Time.now_without_delorean.in_time_zone}"
    # puts "old assumed time is #{old_maybe_fake_time}"
    # puts "new assumed time is #{Time.now.in_time_zone}"

    # keys_prior = @redis.keys('*')

    del = @redis.evalsha(@shift_ttls_sha, ['*'],
            [(dest_time - old_maybe_fake_time).to_i])

    # keys_after = @redis.keys('*')

    # puts "Expired #{del} key#{(del == 1) ? '' : 's'}, #{(keys_prior - keys_after).inspect}"
  end

end

config = Flapjack::Configuration.new
redis_opts = config.load(FLAPJACK_CONFIG) ?
             config.for_redis.merge(:driver => :ruby) :
             {:db => 14, :driver => :ruby}
redis = ::Redis.new(redis_opts)
redis.flushdb
RedisDelorean.before_all(:redis => redis)
redis.quit

# Not the most efficient of operations...
def redis_peek(queue, start = 0, count = nil)
  size = @notifier_redis.llen(queue)
  start = 0 if start < 0
  count = (size - start) if count.nil? || (count > (size - start))

  (0..(size - 1)).inject([]) do |memo, n|
    object = @notifier_redis.rpoplpush(queue, queue)
    next memo unless (n >= start || n < (start + count))
    memo << Flapjack.load_json(object)
    memo
  end
end

Around do |scenario, blk|
  EM.synchrony do
    blk.call
    EM.stop
  end
end

Before do
  @redis_opts = redis_opts
  @logger = MockLogger.new
end

After do
  @logger.messages = []
  @redis_opts = nil
end

Before('@processor') do
  @processor = Flapjack::Processor.new(:logger => @logger,
    :redis_config => redis_opts, :config => {})
  @redis = @processor.instance_variable_get('@redis')
end

After('@processor') do
  @redis.flushdb
  @redis.quit
  @redis = nil
end

Before('@notifier') do
  @notifier = Flapjack::Notifier.new(:logger => @logger,
    :redis_config => redis_opts,
    :config => {'email_queue' => 'email_notifications',
                'sms_queue' => 'sms_notifications',
                'sms_nexmo_queue' => 'sms_nexmo_notifications',
                'sns_queue' => 'sns_notifications',
                'default_contact_timezone' => 'America/New_York'})
  @notifier_redis = @notifier.instance_variable_get('@redis')
end

After('@notifier') do
  @notifier_redis.flushdb
  @notifier_redis.quit
  @notifier_redis = nil
end

Before('@time') do
  RedisDelorean.before_each(:redis => @redis || @notifier_redis)
end

After('@time') do
  Delorean.back_to_the_present
end

After('@process') do
  ['tmp/cucumber_cli/flapjack_cfg.yaml',
   'tmp/cucumber_cli/flapjack_cfg.yaml.bak',
   'tmp/cucumber_cli/flapjack_cfg_d.yaml',
   'tmp/cucumber_cli/flapjack.log',
   'tmp/cucumber_cli/flapjack.pid',
   'tmp/cucumber_cli/nagios_perfdata.fifo',
   'tmp/cucumber_cli/flapjack-nagios-receiver.pid',
   'tmp/cucumber_cli/flapjack-nagios-receiver.log',
   'tmp/cucumber_cli/flapjack-nagios-receiver_d.yaml',
   'tmp/cucumber_cli/flapjack-nagios-receiver.yaml',
   'tmp/cucumber_cli/flapper.pid',
   'tmp/cucumber_cli/flapper.log',
   'tmp/cucumber_cli/flapjack-populator.yaml',
   'tmp/cucumber_cli/flapjack-populator-contacts.json',
   'tmp/cucumber_cli/flapjack-populator-entities.json',
  ].each do |file|
    next unless File.exists?(file)
    File.unlink(file)
  end
end


