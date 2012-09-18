#!/usr/bin/env ruby

# This class encapsulates the config data and environmental setup used
# by the various Flapjack components. It might be easier to split this out
# to those classes, as they tend to be doing different things anyway.
#
# "In Australia and New Zealand, small pancakes (about 75 mm in diameter) known as pikelets
# are also eaten. They are traditionally served with jam and/or whipped cream, or solely
# with butter, at afternoon tea, but can also be served at morning tea."
#    from http://en.wikipedia.org/wiki/Pancake

require 'log4r'
require 'log4r/outputter/consoleoutputters'
require 'log4r/outputter/syslogoutputter'

module Flapjack
  module Pikelet
    attr_accessor :logger, :config

    def bootstrapped?
      !!@bootstrapped
    end

    def should_quit?
      @should_quit
    end

    def stop
      @should_quit = true
    end

    def bootstrap(opts = {})
      return if bootstrapped?

      unless @logger = opts[:logger]
        @logger = Log4r::Logger.new("#{self.class.to_s.downcase.gsub('::', '-')}")
        @logger.add(Log4r::StdoutOutputter.new("flapjack"))
        @logger.add(Log4r::SyslogOutputter.new("flapjack"))
      end

      @config = opts[:config] || {}

      @should_quit = false

      @bootstrapped = true
    end

  end
end
