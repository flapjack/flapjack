require 'spec_helper'

require 'flapjack/redis_proxy'

describe Flapjack::RedisProxy do

  let(:options) { double('options') }

  it "does not initialize the Redis connection immediately" do
    Redis.should_not_receive(:new)

    proxy = Flapjack::RedisProxy.new
  end

  it "proxies commands through to the underlying Redis connection" do
    Flapjack::RedisProxy.should_receive(:config).and_return(options)

    redis = double(Redis)
    redis.should_receive(:keys).with('*')
    Redis.should_receive(:new).with(options).and_return(redis)

    proxy = Flapjack::RedisProxy.new
    proxy.keys('*')
  end

  it "does not initialize the Redis connection on quit if never used" do
    Redis.should_not_receive(:new)

    proxy = Flapjack::RedisProxy.new
    proxy.quit
  end

end
