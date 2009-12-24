#!/usr/bin/env ruby 


class MockLogger
  attr_reader :messages
  %w(warning error info debug).each do |type|
    class_eval <<-HERE
      def #{type}(message)
        @messages ||= []
        @messages << message
      end
    HERE
  end
end

