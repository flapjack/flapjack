#!/usr/bin/env ruby

# defer initialisation for Redis connections until they're used.

module Flapjack

  class RedisProxy

    def initialize(options = {})
      @options = options
    end

    def method_missing(name, *args, &block)
      proxied_connection.send(name, *args, &block)
    end

    private

    def proxied_connection
      @proxied_connection ||= Redis.new(@options)
    end

  end

end
