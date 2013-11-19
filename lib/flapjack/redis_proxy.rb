#!/usr/bin/env ruby

# defer initialisation for Redis connections until they're used.
require 'redis'
require 'redis/connection/hiredis'

module Flapjack

  class << self
    # Thread and fiber-local
    def redis
      redis_cxn = Thread.current[:flapjack_redis]
      return redis_cxn unless redis_cxn.nil?
      Thread.current[:flapjack_redis] = Flapjack::RedisProxy.new
    end
  end

  class RedisProxy

    class << self
      attr_accessor :config
    end

    def quit
      return if @proxied_connection.nil?
      @proxied_connection.quit
    end

    def method_missing(name, *args, &block)
      proxied_connection.send(name, *args, &block)
    end

    private

    def proxied_connection
      @proxied_connection ||= ::Redis.new(self.class.config)
    end

  end

end

