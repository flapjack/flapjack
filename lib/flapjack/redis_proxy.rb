#!/usr/bin/env ruby

# defer initialisation for Redis connections until they're used.
require 'redis'
require 'redis/connection/hiredis'
require 'zermelo'

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

    def initialize
      @proxied_connection = nil
      @connection_failed = nil
    end

    # need to override Kernel.exec
    def exec
      proxied_connection.exec
    end

    def quit
      @proxied_connection.quit unless @connection_failed || @proxied_connection.nil?
    end

    def respond_to?(name, include_private = false)
      proxied_connection.respond_to?(name, include_private)
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
        ((redis_version.split('.') <=> REQUIRED_VERSION.split('.')) >= 0)
      raise("Redis too old - Flapjack requires #{REQUIRED_VERSION} but " \
            "#{redis_version} is running")
    rescue Redis::CannotConnectError, Errno::EINVAL
      @connection_failed = true
      raise
    end

  end

end
