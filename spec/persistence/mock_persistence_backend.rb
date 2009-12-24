#!/usr/bin/env ruby 


module Flapjack
  module Persistence
    class MockPersistenceBackend
      def initialize(options={})
        @options = options
        @config = OpenStruct.new(@options)
        @queue = []
        @log = @config.log
      end

      # log if the method is called (essentially, these are dodgy mocks)
      %w(any_parents_failed? save create_event).each do |method|
        class_eval <<-HERE
          def #{method}(*args)
            @log.info("method #{method} was called on MockPersistenceBackend")
          end
        HERE
      end
    
    end
  end
end

