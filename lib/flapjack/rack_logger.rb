#!/usr/bin/env ruby

module Flapjack

  class CommonLogger < Rack::CommonLogger

    alias_method :orig_log, :log

    private

    def log(env, status, header, began_at)
      ret = orig_log(env, status, header, began_at)
      @logger.flush if @logger.is_a?(Flapjack::AsyncLogger)
      ret
    end

  end

  # from http://stackoverflow.com/questions/6427033/how-do-i-log-asynchronous-thinsinatrarack-requests
 class AsyncLogger < ::Logger

    attr_accessor :messages

    def initialize(logdev, shift_age = 0, shift_size = 1048576)
      @messages = {}
      super(logdev, shift_age, shift_size)
    end

    def write(message)
      stack << message
    end

    def stack
      # This is the important async awareness
      # It stores messages for each fiber separately
      @messages[Fiber.current.object_id] ||= []
    end

    def flush
      stack.each do |msg|
        self.send(:"<<", msg)
      end
      @messages.delete(Fiber.current.object_id)
    end
  end

end
