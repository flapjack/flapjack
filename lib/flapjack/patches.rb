#!/usr/bin/env ruby

require 'thin'
require 'resque'
require 'redis'

# we don't want to stop the entire EM reactor when we stop a web server
# & @connections data type changed in thin 1.5.1
module Thin

  # see https://github.com/flpjck/flapjack/issues/169
  class Request
    class EqlTempfile < ::Tempfile
      def eql?(obj)
        obj.equal?(self) && (obj == self)
      end
    end

    def move_body_to_tempfile
      current_body = @body
      current_body.rewind
      @body = Thin::Request::EqlTempfile.new(BODY_TMPFILE)
      @body.binmode
      @body << current_body.read
      @env[RACK_INPUT] = @body
    end
  end

  module Backends
    class Base
      def stop!
        @running  = false
        @stopping = false

        # EventMachine.stop if EventMachine.reactor_running?

        case @connections
        when Array
          @connections.each { |connection| connection.close_connection }
        when Hash
          @connections.each_value { |connection| connection.close_connection }
        end
        close
      end
    end
  end
end

# Resque is really designed around a multiprocess model, so we here we
# stub some that behaviour away.
module Resque

  class Worker

    def procline(string)
      # $0 = "resque-#{Resque::Version}: #{string}"
      # log! $0
    end

    # Redefining the entire method to stop the direct access to $0 :(
    def work(interval = 5.0, &block)
      interval = Float(interval)
      # $0 = "resque: Starting"
      startup

      loop do

        break if shutdown?

        if not paused? and job = reserve
          log "got: #{job.inspect}"
          job.worker = self
          run_hook :before_fork, job
          working_on job

          if @child = fork
            srand # Reseeding
            procline "Forked #{@child} at #{Time.now.to_i}"
            Process.wait(@child)
          else
            unregister_signal_handlers if !@cant_fork && term_child
            procline "Processing #{job.queue} since #{Time.now.to_i}"
            redis.client.reconnect if !@cant_fork # Don't share connection with parent
            perform(job, &block)
            exit! unless @cant_fork
          end

          done_working
          @child = nil
        else
          break if interval.zero?
          log! "Sleeping for #{interval} seconds"
          procline paused? ? "Paused" : "Waiting for #{@queues.join(',')}"
          sleep interval
        end
      end

      unregister_worker
    rescue Exception => exception
      unregister_worker(exception)
    end

  end
end

# As Redis::Future objects inherit from BasicObject, it's difficult to
# distinguish between them and other objects in collected data from
# pipelined queries.
#
# (One alternative would be to put other values in Futures ourselves, and
#  evaluate everything...)
class Redis
  class Future
    def class
      ::Redis::Future
    end
  end
end
