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
        result = YAML::load(job.body)
        Flapjack::QueueBackends::Result.new(:job => job, :result => result)
      end

      def delete(result)
        result.job.delete
      end
    end
  end
end

module Flapjack
  module QueueBackends
    class Result

      attr_accessor :job

      def initialize(options={})
        @job = options[:job]
        @result = OpenStruct.new(YAML::load(@job.body))
      end
  
      # Whether a check returns an ok status. 
      def ok?
        @result.retval == 0
      end
    
      # Whether a check has a warning status.
      def warning?
        @result.retval == 1
      end
    
      # Whether a check has a critical status.
      def critical?
        @result.retval == 2
      end
    
      # Human readable representation of the check's return value.
      def status
        case @result.retval
        when 0 ; "ok"
        when 1 ; "warning"
        when 2 ; "critical"
        end
      end
    
      def id
        # openstruct won't respond, so we have to manually define it
        @result.check_id
      end

    end
  end
end
