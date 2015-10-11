require 'spec_helper'

require 'flapjack/redis_proxy'

describe Flapjack::RedisProxy do

  let(:options) { double('options') }

  it "does not initialize the Redis connection immediately" do
    expect(Redis).not_to receive(:new)

    Flapjack::RedisProxy.new
  end

  it "proxies commands through to the underlying Redis connection" do
    expect(Flapjack::RedisProxy).to receive(:config).and_return(options)

    redis = double(Redis)
    expect(redis).to receive(:info).and_return({'redis_version' => '2.8.17'})
    expect(redis).to receive(:keys).with('*')
    expect(Redis).to receive(:new).with(options).and_return(redis)

    proxy = Flapjack::RedisProxy.new
    proxy.keys('*')
  end

  it "throws an exception when redis is too old" do
    expect(Flapjack::RedisProxy).to receive(:config).and_return(options)

    redis = double(Redis)
    expect(redis).to receive(:info).and_return({'redis_version' => '2.1.1'})
    expect(Redis).to receive(:new).with(options).and_return(redis)

    proxy = Flapjack::RedisProxy.new
    expect {proxy.keys('*')}.to raise_exception(RuntimeError, 'Redis too old - Flapjack requires 2.6.12 but 2.1.1 is running')
  end

  it "does not initialize the Redis connection on quit if never used" do
    expect(Redis).not_to receive(:new)

    proxy = Flapjack::RedisProxy.new
    proxy.quit
  end

end
