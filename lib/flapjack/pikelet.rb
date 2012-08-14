#!/usr/bin/env ruby

# Encapsulates the config loading and environment setup used
# by the various Flapjack components

require 'log4r/outputter/consoleoutputters'
require 'log4r/outputter/syslogoutputter'

module Flapjack
  module Pikelet
    
    attr_accessor :bootstrapped, :persistence, :logger, :config

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

      @persistence = EM::Protocols::Redis.connect(options[:redis])

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