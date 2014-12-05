#!/usr/bin/env ruby

# defer initialisation for Redis connections until they're used.
require 'redis'
require 'redis/connection/hiredis'
require 'sandstorm'

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

    REQUIRED_VERSION = '2.6.12'

    def proxied_connection
      return @proxied_connection unless @proxied_connection.nil?
      @proxied_connection = ::Redis.new(self.class.config)
      redis_version = @proxied_connection.info['redis_version']
      return @proxied_connection if redis_version.nil? ||
      (redis_version.split('.') <=> REQUIRED_VERSION.split('.')) >= 0
      raise "Redis too old - Flapjack requires #{REQUIRED_VERSION} but #{redis_version} is running"
    end

  end

end
