#!/usr/bin/env ruby 


module Flapjack
  module Transport
    class Mocktransport
      def initialize(options={})
        @options = options
        @config = OpenStruct.new(@options)
        @queue = []
        @log = @config.log
      end

      %w(delete put).each do |method|
        class_eval <<-HERE
          def #{method}(*args)
            @log.info("method #{method} was called on #{self.class.to_s.split('::').last}")
          end
        HERE
      end

      # exactly the same as above, just returns a real object
      def next
        @log.info("method next was called on #{self.class.to_s.split('::').last}")
        MockResult.new(@options)
      end


    end
  end
end

module Flapjack
  module Transport
    class MockResult
      def initialize(options={})
        @options = options
        @config = OpenStruct.new(@options)
        @log = @config.log
      end

      # log if the method is called (essentially, these are dodgy mocks)
      %w(warning? critical? any_parents_failed? save check_id frequency).each do |method|
        class_eval <<-HERE
          def #{method}(*args)
            @log.info("method #{method} was called on #{self.class.to_s.split('::').last}")
          end
        HERE
      end

      # exactly the same as above, just returns a real object
      def command(*args)
        @log.info("method command was called on #{self.class.to_s.split('::').last}")
        "echo foo"
      end
    end
  end
end
