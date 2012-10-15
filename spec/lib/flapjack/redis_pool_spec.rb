require 'spec_helper'
require 'flapjack/redis_pool'

describe Flapjack::RedisPool do

  it "is initialized, and emptied" do
    EM.synchrony do
      redis_count = 3

      redis_conns = redis_count.times.collect {
        redis = mock('redis')
        redis.should_receive(:quit)
        redis
      }
      ::Redis.should_receive(:new).exactly(redis_count).times.and_return(*redis_conns)

      frp = Flapjack::RedisPool.new(:size => redis_count)
      frp.empty!

      EM.stop
    end
  end

end