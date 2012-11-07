#!/usr/bin/env ruby

# This class encapsulates the config data and environmental setup used
# by the various Flapjack components.
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

    # Classes including a pikelet subclass and wanting to extend #bootstrap
    # should alias the original method and make sure to call them
    # as part of their interstitial method.
    def bootstrap(opts = {})
      return if @bootstrapped

      unless @logger = opts[:logger]
        @logger = Log4r::Logger.new("#{self.class.to_s.downcase.gsub('::', '-')}")
        @logger.add(Log4r::StdoutOutputter.new("flapjack"))
        @logger.add(Log4r::SyslogOutputter.new("flapjack"))
      end

      @config = opts[:config] || {}

      @bootstrapped = true
    end

    # Aliasing isn't currently necessary for #cleanup, as it's empty anyway.
    # It's probably best practice to do so, in case that changes.
    def cleanup
    end

  end

  module GenericPikelet
    include Flapjack::Pikelet

    def should_quit?
      @should_quit
    end

    def stop
      @should_quit = true
    end

    alias_method :orig_bootstrap, :bootstrap

    def bootstrap(opts = {})
      @should_quit = false

      orig_bootstrap(opts)
    end

  end

  module ResquePikelet
    include Flapjack::Pikelet
  end

  module ThinPikelet
    include Flapjack::Pikelet

    attr_accessor :port

    alias_method :orig_bootstrap, :bootstrap

    def bootstrap(opts = {})
      return if @bootstrapped

      if config = opts[:config]
        @port = config['port'] ? config['port'].to_i : nil
        @port = 3001 if (@port.nil? || @port <= 0 || @port > 65535)
      end

      orig_bootstrap(opts)
    end

  end
end
