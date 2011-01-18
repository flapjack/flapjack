#!/usr/bin/env ruby

$: << File.expand_path(File.join(File.dirname(__FILE__), '..', '..'))
require 'beanstalk-client'
require 'flapjack/transports/result'

module Flapjack
  module Transport
    class Beanstalkd
      def initialize(options={})
        @options = options
        @config = OpenStruct.new(options)
        @log    = @config.log

        unless @config.host && @config.port && @config.queue_name
          raise ArgumentError, "You need to specify a beanstalkd host, port, and queue name to connect to."
        end

        connect
      end

      def connect
        begin
          @queue = Beanstalk::Pool.new(["#{@config.host}:#{@config.port}"], @config.queue_name)
        rescue Beanstalk::NotConnected => e
          @log.error("Couldn't connect to the '#{@config.queue_name}' Beanstalk queue. Waiting 5 seconds, then retrying.")
          sleep 5
          retry
        end
      end

      def next
        begin
          job = @queue.reserve # blocks
          result = YAML::load(job.body)
          Flapjack::Transport::Result.new(:job => job, :result => result)
        rescue Beanstalk::NotConnected
          @log.error("The '#{@config.queue_name}' Beanstalk queue went away. Waiting 5 seconds, then retrying.")
          sleep 5
          retry
        end
      end

      def delete(result)
        result.job.delete
      end
    end
  end
end

