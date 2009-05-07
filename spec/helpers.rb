#!/usr/bin/env ruby 


class MockLogger
  attr_reader :messages
  def initialize 
    @messages = []
  end

  %w(warning error info).each do |type|
    class_eval <<-HERE
      def #{type}(message)
        @messages << message
      end
    HERE
  end
end

