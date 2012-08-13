#!/usr/bin/env ruby

# Encapsulates the config loading and environment setup used
# by the various Flapjack components

require 'log4r/outputter/consoleoutputters'
require 'log4r/outputter/syslogoutputter'

module Flapjack
  module Pikelet
    
    attr_accessor :bootstrapped, :persistence, :logger, :config
        
    # FIXME: this should register the running pikelet as a unique instance in redis
    # perhaps look at resque's code, how it does this
    def instance
      1
    end

    def bootstrapped?
      !!@bootstrapped
    end
    
    def bootstrap(opts = {})
      return if bootstrapped?
      
      defaults = {
        :redis => {
          :db => 0
        }
      }
      options = defaults.merge(opts)

      @persistence = ::Redis.new(options[:redis])

      unless @logger = options[:logger]
        @logger = Log4r::Logger.new("flapjack")
        @logger.add(Log4r::StdoutOutputter.new("flapjack"))
        @logger.add(Log4r::SyslogOutputter.new("flapjack"))
      end

      @config  = options[:config] || {}

      @bootstrapped = true
    end
      
  end
end