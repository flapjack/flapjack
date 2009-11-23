#!/usr/bin/env ruby

require 'beanstalk-client'

module Flapjack
  module QueueBackends
    class Beanstalkd
      def initialize(options={})
        @options = options
        @config = OpenStruct.new(options)

        unless @config.host && @config.port && @config.queue_name
          raise ArgumentError, "You need to specify a beanstalkd host, port, and queue name to connect to."
        end

        @queue = Beanstalk::Pool.new(["#{@config.host}:#{@config.port}"], @config.queue_name)
      end

      def next
        job = @queue.reserve # blocks
        Flapjack::QueueBackends::Result.new(:job => job)
      end

      def delete(job)
        job.delete
      end
    end
  end
end

module Flapjack
  module QueueBackends
    class Result
      def initialize(options={})
        @job = OpenStruct.new(YAML::load(options[:job].body))
      end
  
      # Whether a check returns an ok status. 
      def ok?
        @job.retval == 0
      end
    
      # Whether a check has a warning status.
      def warning?
        @job.retval == 1
      end
    
      # Whether a check has a critical status.
      def critical?
        @job.retval == 2
      end
    
      # Human readable representation of the check's return value.
      def status
        case @job.retval
        when 0 ; "ok"
        when 1 ; "warning"
        when 2 ; "critical"
        end
      end
    
      def id
        # openstruct won't respond, so we have to manually define it
        @job.id
      end

      def save 
      end

      def delete
      end
  
    end
  end
end
