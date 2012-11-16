#!/usr/bin/env ruby

# This class encapsulates the config data and environmental setup used
# by the various Flapjack components.
#
# "In Australia and New Zealand, small pancakes (about 75 mm in diameter) known as pikelets
# are also eaten. They are traditionally served with jam and/or whipped cream, or solely
# with butter, at afternoon tea, but can also be served at morning tea."
#    from http://en.wikipedia.org/wiki/Pancake

require 'log4r'
require 'log4r/formatter/patternformatter'
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
        logger_name = self.class.to_s.downcase.gsub('::', '-')
        @logger = Log4r::Logger.new(logger_name)

        formatter = Log4r::PatternFormatter.new(:pattern => "[%l] %d :: #{logger_name} :: %m",
          :date_pattern => "%Y-%m-%dT%H:%M:%S%z")

        [Log4r::StdoutOutputter, Log4r::SyslogOutputter].each do |outp_klass|
          outp = outp_klass.new(logger_name)
          outp.formatter = formatter
          @logger.add(outp)
        end
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

end
