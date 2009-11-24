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

