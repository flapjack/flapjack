#!/usr/bin/env ruby 


module Flapjack
  module QueueBackends
    class Mockbackend
      def initialize(options={})
        @options = options
        @config = OpenStruct.new(@options)
        @queue = []
        @log = @config.log
      end

      def next
        @log.info("method next was called on Mockbackend")
        Result.new(@options)
      end
    end
  end
end

module Flapjack
  module QueueBackends
    class Result
      def initialize(options={})
        @options = options
        @config = OpenStruct.new(@options)
        @log = @config.log
      end

      # log if the method is called (essentially, these are dodgy mocks)
      %w(id warning? critical? any_parents_failed? save delete).each do |method|
        class_eval <<-HERE
          def #{method}(*args)
            @log.info("method #{method} was called on Result")
          end
        HERE
      end
    end
  end
end
