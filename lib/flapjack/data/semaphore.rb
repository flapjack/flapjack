#!/usr/bin/env ruby

require 'securerandom'

module Flapjack
  module Data

    # http://redis.io/commands/set
    class Semaphore

      SEMAPHORE_KEYSPACE = 'semaphores:'

      attr_reader :token, :expiry, :resource

      class ResourceLocked < RuntimeError
      end

      def initialize(resource, options)
        raise "redis connection must be passed in options" unless @redis = options[:redis]
        @resource = resource
        @token    = options[:token]  || SecureRandom.uuid
        @expiry   = options[:expiry] || 30

        @key = "#{SEMAPHORE_KEYSPACE}#{@resource}"

        raise Flapjack::Data::Semaphore::ResourceLocked.new unless @redis.set(@key, @token, {:nx => true, :ex => @expiry})
      end

      def release
        unlock_script = '
         if redis.call("get",KEYS[1]) == ARGV[1]
          then
            return redis.call("del",KEYS[1])
          else
            return 0
          end
        '
        @redis.eval(unlock_script, [@key], [@token])
      end

    end
  end
end

