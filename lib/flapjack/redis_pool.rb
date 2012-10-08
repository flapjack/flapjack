#!/usr/bin/env ruby

require 'eventmachine'
# the redis/synchrony gems need to be required in this particular order, see
# the redis-rb README for details
require 'hiredis'
require 'em-synchrony'
require 'redis/connection/synchrony'
require 'redis'

# require 'eventmachine/synchrony/connection_pool'

module Flapjack
  class RedisPool < EventMachine::Synchrony::ConnectionPool

    def initialize(opts = {})
      config = opts.delete(:config)
      super(:size => opts[:size] || 5) {
        ::Redis.new(config)
      }
    end

    def empty!
      f = Fiber.current

      until @available.empty? && @pending.empty?
        begin
          conn = acquire(f)
          conn.quit
          @available.delete(conn)
        ensure
          if pending = @pending.shift
            pending.resume
          end
        end
      end
    end

  end
end