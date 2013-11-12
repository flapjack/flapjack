#!/usr/bin/env ruby

# Copied from the connection_pool gem ( https://github.com/mperham/connection_pool/ ),
# with some further changes:
#
# * allows non-timeout connections, needed for Redis blpop etc.
# * adjusts size dynamically

module Flapjack

  class PoolShuttingDownError < RuntimeError; end

  class ConnectionPool

    class ConnectionStack

      def initialize(size = 0)
        @que = Array.new(size) { yield }
        @mutex = Mutex.new
        @resource = ConditionVariable.new
        @shutdown_block = nil
      end

      def push(obj)
        @mutex.synchronize do
          if @shutdown_block
            @shutdown_block.call(obj)
          else
            @que.push obj
          end

          @resource.broadcast
        end
      end
      alias_method :<<, :push

      def pop(timeout = 0.5)
        deadline = (timeout && (timeout > 0)) ? (Time.now + timeout) : nil
        @mutex.synchronize do
          loop do
            raise ::Flapjack::PoolShuttingDownError if @shutdown_block
            return @que.pop unless @que.empty?
            if deadline
              to_wait = deadline - Time.now
              raise Timeout::Error, "Waited #{timeout} sec" if to_wait <= 0
              @resource.wait(@mutex, to_wait)
            else
              @resource.wait(@mutex)
            end
          end
        end
      end

      def shutdown(&block)
        raise ArgumentError, "shutdown must receive a block" unless block_given?

        @mutex.synchronize do
          @shutdown_block = block
          @resource.broadcast

          @que.size.times do
            conn = @que.pop
            block.call(conn)
          end
        end
      end

      def empty?
        @que.empty?
      end

      def length
        @que.length
      end
    end


    DEFAULTS = {:size => 5, :timeout => nil}

    def self.wrap(options, &block)
      Flapjack::ConnectionPool::Wrapper.new(options, &block)
    end

    def initialize(options = {})
      raise ArgumentError, 'Connection pool requires init and shutdown blocks' unless
        options[:init] && options[:shutdown]

      options = DEFAULTS.merge(options)

      @init_block     = options[:init]
      @shutdown_block = options[:shutdown]
      @size           = options[:size]
      @timeout        = options[:timeout]

      @available = Flapjack::ConnectionPool::ConnectionStack.new(@size, &@init_block)
      @key = :"current-#{@available.object_id}"
    end

    def with
      conn = checkout
      yield conn
    ensure
      checkin(conn)
    end

    def checkout
      @available.pop(@timeout)
    end

    def checkin(conn)
      @available << conn
    end

    def adjust_size(new_size)
      diff = new_size - @available.length
      return if diff == 0
      if diff > 0
        diff.times {|i| @available << @init_block.call }
        return
      end
      diff.abs.times {|i| @shutdown_block.call(checkout) }
    end

    def shutdown
      @available.shutdown(&@shutdown_block)
    end

    class Wrapper < ::BasicObject
      METHODS = [:with, :pool_shutdown]

      def initialize(options = {})
        @pool = ::Flapjack::ConnectionPool.new(options)
      end

      def with
        conn = @pool.checkout
        yield(conn)
      ensure
        @pool.checkin(conn)
      end

      def pool_shutdown
        @pool.shutdown
      end

      def pool_adjust_size(new_size)
        @pool.adjust_size(new_size)
      end

      def respond_to?(id, *args)
        METHODS.include?(id) || @pool.with { |c| c.respond_to?(id, *args) }
      end

      def method_missing(name, *args, &block)
        @pool.with do |connection|
          connection.send(name, *args, &block)
        end
      end
    end

  end

end
