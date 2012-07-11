#!/usr/bin/env ruby

require 'flapjack/event'
require 'redis'
require 'json'

module Flapjack
  class Events
    def initialize
      @redis = ::Redis.new
      @key   = 'events'
    end

    def next
      raw   = @redis.blpop(@key).last
      event = ::JSON.parse(raw)
      Flapjack::Event.new(event)
    end

    # non blocking version of next
    def gimmie
      lpops = @redis.lpop(@key)
      pp lpops
      raw   = lpops.last
      pp raw
      event = ::JSON.parse(raw)
      Flapjack::Event.new(event)
    end

    def size
      @redis.llen(@key)
    end
  end
end

