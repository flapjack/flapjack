#!/usr/bin/env ruby

module Flapjack
  def self.bootstrap(opts={})
    if not bootstrapped?
      defaults = {
        :redis => {
          :db => 0
        }
      }
      @options = defaults.merge(opts)

      @@persistence = ::Redis.new(@options[:redis])

      if not @@logger = @options[:logger]
        @@logger = Log4r::Logger.new("executive")
        @@logger.add(Log4r::StdoutOutputter.new("executive"))
        @@logger.add(Log4r::SyslogOutputter.new("executive"))
      end
    end

    @bootstrapped = true
  end

  def self.bootstrapped?
    @bootstrapped
  end

  def self.persistence
    @@persistence
  end

  def self.logger
    @@logger
  end
end

