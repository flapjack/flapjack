#!/usr/bin/env ruby

require 'set'
require 'redis'

module Flapjack
  module Data

    class Tag < ::Set

      attr_accessor :name

      def initialize(opts)
        @name  = opts[:name]
        @redis = opts[:redis]
        preset = @redis.smembers(@name)
        enum = opts[:create] || []
        @redis.sadd(@name, enum) unless enum.empty?
        super(enum | preset)
      end

      def self.find(name, opts)
        self.new(:name => name,
                 :redis => opts[:redis])
      end

      def self.find_intersection(tags, opts)
        @redis = opts[:redis]
        @redis.sinter(tags)
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

    end
  end
end

