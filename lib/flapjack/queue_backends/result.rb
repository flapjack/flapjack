#!/usr/bin/env ruby

module Flapjack
  module QueueBackends
    class Result

      attr_accessor :job, :result

      def initialize(options={})
        @job = options[:job]
        raw_job = YAML::load(@job.body)
        raw_job[:check_id] ||= raw_job.delete(:id)
        @result = OpenStruct.new(raw_job)
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
