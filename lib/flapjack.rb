#!/usr/bin/env ruby

module Flapjack
  def self.bootstrap(opts={})
    if not bootstrapped?
      defaults = {
        :redis => {
          :db => 0
        }
      }
      @options     = defaults.merge(opts)

      @@persistence = ::Redis.new(@options[:redis])
    end

    @bootstrapped = true
  end

  def self.bootstrapped?
    @bootstrapped
  end

  def self.persistence
    @@persistence
  end
end

