#!/usr/bin/env ruby

module Flapjack
  class RackLogger < ::Logger
    # Works around a 1.8-specific call to a Logger method in Rack::CommonLogger
    def write(msg); self.send(:"<<", msg); end
  end
end