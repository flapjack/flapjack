#!/usr/bin/env ruby

# Resque is really designed around a multiprocess model, so we here we
# stub some that behaviour away.

require 'resque'

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