#!/usr/bin/env ruby

require 'set'
require 'redis'

module Flapjack
  module Data

    class Tag < ::Set

      attr_accessor :name

      def initialize(opts = {})
        @name  = opts[:name]
        preset = Flapjack.redis.smembers(@name)
        enum = opts[:create] || []
        Flapjack.redis.sadd(@name, enum) unless enum.empty?
        super(enum | preset)
      end

      def self.find(name)
        self.new(:name => name)
      end

      def self.find_intersection(tags)
        Flapjack.redis.sinter(tags)
      end

      def self.create(name, enum = [])
        self.new(:name => name, :create => enum)
      end

      def add(o)
        Flapjack.redis.sadd(@name, o) unless o.empty?
        super(o)
      end

      def delete(o)
        Flapjack.redis.srem(@name, o)
        super(o)
      end

      def merge(o)
        Flapjack.redis.sadd(@name, o) unless o.empty?
        super(o)
      end

      def to_json(*a)
        self.to_a.to_json(*a)
      end

    end
  end
end

