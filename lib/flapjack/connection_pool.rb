#!/usr/bin/env ruby

# Copied from the connection_pool gem ( https://github.com/mperham/connection_pool/ )
# and altered to allow non-timeout connections, needed for the blocking Redis
# connections.

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

    def initialize(options = {}, &block)
      raise ArgumentError, 'Connection pool requires a block' unless block

      options = DEFAULTS.merge(options)

      @size = options.fetch(:size)
      @timeout = options.fetch(:timeout)

      @available = Flapjack::ConnectionPool::ConnectionStack.new(@size, &block)
      @key = :"current-#{@available.object_id}"
    end

    def with
      conn = checkout
      begin
        yield conn
      ensure
        checkin
      end
    end

    def checkout
      stack = ::Thread.current[@key] ||= []

      if stack.empty?
        conn = @available.pop(@timeout)
      else
        conn = stack.last
      end

      stack.push conn
      conn
    end

    def checkin
      stack = ::Thread.current[@key]
      conn = stack.pop
      if stack.empty?
        @available << conn
      end
      nil
    end

    def shutdown(&block)
      @available.shutdown(&block)
    end

    class Wrapper < ::BasicObject
      METHODS = [:with, :pool_shutdown]

      def initialize(options = {}, &block)
        @pool = ::Flapjack::ConnectionPool.new(options, &block)
      end

      def with
        yield @pool.checkout
      ensure
        @pool.checkin
      end

      def pool_shutdown(&block)
        @pool.shutdown(&block)
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
