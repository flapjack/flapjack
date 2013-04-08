#!/usr/bin/env ruby

require 'set'
require 'redis'

module Flapjack
  module Data

    class Tag < ::Set

      attr_accessor :name

      def initialize(opts = {})
        raise "Redis connection not set" unless @redis = opts[:redis]

        @name  = opts[:name]
        preset = @redis.smembers(@name)
        enum = opts[:create] || []
        @redis.sadd(@name, enum) unless enum.empty?
        super(enum | preset)
      end

      def self.find(name, opts)
        self.new(:name => name,
                 :redis => opts[:redis])
      end

      def self.create(name, enum = [], opts)
        self.new(:name => name,
                 :create => enum,
                 :redis => opts[:redis])
      end

      def add(o)
        @redis.sadd(@name, o) unless o.empty?
        super(o)
      end

      def delete(o)
        @redis.srem(@name, o)
        super(o)
      end

      def merge(o)
        @redis.sadd(@name, o) unless o.empty?
        super(o)
      end

      def to_json(*a)
        self.to_a.to_json(*a)
      end

    end
  end
end

