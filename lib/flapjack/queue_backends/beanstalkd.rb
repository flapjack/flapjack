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
    end
  end
end
