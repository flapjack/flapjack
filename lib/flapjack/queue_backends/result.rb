#!/usr/bin/env ruby

module Flapjack
  module QueueBackends
    class Result

      attr_accessor :job, :result

      def initialize(options={})
        @job = options[:job]
        @result = OpenStruct.new(options[:result])
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
        @result.check_id
      end

      def check_id
        @result.check_id
      end

    end
  end
end
