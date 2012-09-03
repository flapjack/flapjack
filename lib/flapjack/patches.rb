#!/usr/bin/env ruby

require 'ostruct'
require 'daemons'
require 'thin'
require 'resque'
# require 'log4r'

class OpenStruct
  def to_h
    @table
  end
end

module Daemons
  class PidFile
    # we override this method so creating pid files is fork-safe
    def filename
      File.join(@dir, "#{@progname}#{Process.pid}.pid")
    end
  end
end

#module Log4r
#  class Logger
#    def error(args)
#      err(args)
#    end
#
#    def warning(args)
#      warn(args)
#    end
#  end
#end

# extracted from Extlib.
# FIXME: what's the licensing here?
class String
  def camel_case
    return self if self !~ /_/ && self =~ /[A-Z]+.*/
    split('_').map{|e| e.capitalize}.join
  end
end

# http://gist.github.com/151324
class Hash
  def symbolize_keys
    inject({}) do |acc, (k,v)|
      key = String === k ? k.to_sym : k
      value = Hash === v ? v.symbolize_keys : v
      acc[key] = value
      acc
    end
  end
end

# we don't want to stop the entire EM reactor when we stop a web server
module Thin
  module Backends
    class Base
      def stop!
        @running  = false
        @stopping = false

        # EventMachine.stop if EventMachine.reactor_running?
        @connections.each { |connection| connection.close_connection }
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
            procline "Processing #{job.queue} since #{Time.now.to_i}"
            redis.client.reconnect # Don't share connection with parent
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

    ensure
      unregister_worker
    end

  end

end