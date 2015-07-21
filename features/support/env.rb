#!/usr/bin/env ruby

Encoding.default_internal = 'UTF-8'

require 'delorean'
require 'chronic'
require 'active_support/time'
require 'ice_cube'

require 'flapjack/configuration'

if ENV['COVERAGE']
  require 'simplecov'
  SimpleCov.start do
    add_filter '/features/'
  end
  SimpleCov.at_exit do
    # Oj.default_options = { :mode => :compat }
    SimpleCov.result.format!
  end
end

@debug = false

require 'i18n'
I18n.config.enforce_available_locales = true

FLAPJACK_ENV = 'test'
FLAPJACK_ROOT   = File.join(File.dirname(__FILE__), '..', '..')
FLAPJACK_CONFIG = File.join(FLAPJACK_ROOT, 'etc', 'flapjack_test_config.toml')

$: << File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'lib'))

require 'pathname'

require 'webmock/cucumber'
WebMock.disable_net_connect!

require 'flapjack'
require 'flapjack/patches'
require 'flapjack/redis_proxy'

require 'flapjack/data/check'
require 'flapjack/data/event'

require 'flapjack/notifier'
require 'flapjack/processor'

class MockLogger
  attr_accessor :messages

  def self.configure_log(name)
    @name = name
  end

  def initialize
    @messages = []
  end

  %w(debug info warn error fatal).each do |level|
    class_eval <<-RUBY
      def #{level}(msg = nil, &block)
        msg = yield if msg.nil? && block_given?
        @messages << '[#{level.upcase}] :: ' +
          (self.class.instance_variable_get('@name') || 'flapjack') + ' :: ' + msg
      end
    RUBY
  end
end

require 'mail'
Mail.defaults do
  delivery_method :test
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

  def self.before_all
    @shift_ttls_sha = Flapjack.redis.script(:load, ShiftTTLsScript)
  end

  def self.time_travel_to(dest_time)
    old_maybe_fake_time = Time.now.in_time_zone
    Delorean.time_travel_to(dest_time)

    Flapjack.redis.evalsha(@shift_ttls_sha, ['*'],
      [(dest_time - old_maybe_fake_time).to_i])
  end
end

config = Flapjack::Configuration.new
Flapjack::RedisProxy.config = config.load(FLAPJACK_CONFIG) ?
                                config.for_redis :
                                {:db => 14, :driver => :ruby}
Zermelo.redis = Flapjack.redis
Flapjack.redis.flushdb
RedisDelorean.before_all
Flapjack.redis.quit

# Not the most efficient of operations...
def redis_peek(queue, klass, start = 0, count = nil)
  size = Flapjack.redis.llen(queue)
  start = 0 if start < 0
  count = (size - start) if count.nil? || (count > (size - start))

  (0..(size - 1)).inject([]) do |memo, n|
    obj_id = Flapjack.redis.rpoplpush(queue, queue)
    next memo unless (n >= start || n < (start + count)) &&
      (object = klass.find_by_id(obj_id))
    memo << object
    memo
  end
end

Before do
  Flapjack.logger = MockLogger.new
end

After do
  Flapjack.logger.messages = []
  WebMock.reset!
end

Before('@processor') do
  Flapjack.redis.flushdb
  MockLogger.configure_log('flapjack-processor')
  @processor = Flapjack::Processor.new(:boot_time => Time.now,
    :config => {'new_check_scheduled_maintenance_duration' => '0 seconds'})
  @processor.start_stats
end

After('@processor') do
  Flapjack.redis.quit
end

Before('@notifier') do
  Flapjack.redis.flushdb
  MockLogger.configure_log('flapjack-notifier')
  @notifier  = Flapjack::Notifier.new(
    :config => {'email_queue' => 'email_notifications',
                'sms_queue' => 'sms_notifications',
                'sms_nexmo_queue' => 'sms_nexmo_notifications',
                'sns_queue' => 'sns_notifications',
                'default_contact_timezone' => 'America/New_York'})
end

After('@notifier') do
  Flapjack.redis.quit
end

Before('@notifications') do
  Mail::TestMailer.deliveries.clear
end

Before('@not_jruby') do
  pending if 'java'.eql?(RUBY_PLATFORM)
end

After('@time') do
  Delorean.back_to_the_present
end

After('@process') do
  ['tmp/cucumber_cli/flapjack_cfg.toml',
   'tmp/cucumber_cli/flapjack_cfg.toml.bak',
   'tmp/cucumber_cli/flapjack_cfg_d.toml',
   'tmp/cucumber_cli/flapjack.log',
   'tmp/cucumber_cli/flapjack.pid',
   'tmp/cucumber_cli/nagios_perfdata.fifo',
   'tmp/cucumber_cli/flapjack-nagios-receiver.pid',
   'tmp/cucumber_cli/flapjack-nagios-receiver.log',
   'tmp/cucumber_cli/flapjack-nagios-receiver_d.toml',
   'tmp/cucumber_cli/flapjack-nagios-receiver.toml',
   'tmp/cucumber_cli/flapper.pid',
   'tmp/cucumber_cli/flapper.log',
   'tmp/cucumber_cli/flapjack-populator.toml',
   'tmp/cucumber_cli/flapjack-populator-contacts.json',
   'tmp/cucumber_cli/flapjack-populator-entities.json',
  ].each do |file|
    next unless File.exists?(file)
    File.unlink(file)
  end
end
