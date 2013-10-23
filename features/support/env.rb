#!/usr/bin/env ruby
#

require 'delorean'
require 'chronic'
require 'active_support/time'
require 'ice_cube'

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

require 'flapjack/patches'

require 'flapjack/data/entity_check'
require 'flapjack/data/event'

require 'flapjack/notifier'
require 'flapjack/processor'

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

require 'mail'
Mail.defaults do
  delivery_method :test
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

  def self.before_all
     @expire_as_if_at_sha = Flapjack.redis.script(:load, ExpireAsIfAtScript)
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

    result = Flapjack.redis.evalsha(@expire_as_if_at_sha, ['*'],
               [real_time, real_time + delta])
    #puts "Expired #{result} key#{(result == 1) ? '' : 's'}"
  end

end

redis_opts = { :db => 14, :driver => :ruby }
Flapjack.redis = ::Redis.new(redis_opts)
Flapjack.redis.flushdb
RedisDelorean.before_all
Flapjack.redis.quit

# Not the most efficient of operations...
def redis_peek(queue, start = 0, count = nil)
  size = Flapjack.redis.llen(queue)
  start = 0 if start < 0
  count = (size - start) if count.nil? || (count > (size - start))

  (0..(size - 1)).inject([]) do |memo, n|
    obj = Flapjack.redis.rpoplpush(queue, queue)
    memo << Oj::load(obj) if (n >= start || n < (start + count))
    memo
  end
end

Before do
  @logger = MockLogger.new
end

After do
  @logger.messages = []
  WebMock.reset!
end

Before('@processor') do
  @processor = Flapjack::Processor.new(:logger => @logger, :config => {})
end

After('@processor') do
  Flapjack.redis.flushdb
  Flapjack.redis.quit
end

Before('@notifier') do
  @notifier  = Flapjack::Notifier.new(:logger => @logger,
    :config => {'email_queue' => 'email_notifications',
                'sms_queue' => 'sms_notifications',
                'default_contact_timezone' => 'America/New_York'})
end

After('@notifier') do
  Flapjack.redis.flushdb
  Flapjack.redis.quit
end

Before('@notifications') do
  Mail::TestMailer.deliveries.clear
end

After('@time') do
  Delorean.back_to_the_present
end

After('@process') do
  ['tmp/cucumber_cli/flapjack_cfg.yml',
   'tmp/cucumber_cli/flapjack_cfg.yml.bak',
   'tmp/cucumber_cli/flapjack_cfg_d.yml',
   'tmp/cucumber_cli/flapjack_d.log',
   'tmp/cucumber_cli/flapjack_d.pid'].each do |file|
    next unless File.exists?(file)
    File.unlink(file)
  end
end


