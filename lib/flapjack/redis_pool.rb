#!/usr/bin/env ruby

require 'eventmachine'
# the redis/synchrony gems need to be required in this particular order, see
# the redis-rb README for details
require 'hiredis'
require 'em-synchrony'
require 'redis/connection/synchrony'
require 'redis'

require 'em-synchrony/connection_pool'

module Flapjack
  class RedisPool < EventMachine::Synchrony::ConnectionPool

    def initialize(opts = {})
      config = opts.delete(:config)
      @size = opts[:size] || 5
      super(:size => @size) {
        ::Redis.new(config)
      }
    end

  end
end
