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

require 'flapjack/redis_pool'

module Flapjack
  module Pikelet
    attr_accessor :logger, :redis, :config

    def should_quit?
      @should_quit
    end

    def stop
      @should_quit = true
    end

    def build_redis_connection_pool(options = {})
      return unless @bootstrapped
      if defined?(EventMachine) && defined?(EventMachine::Synchrony)
        Flapjack::RedisPool.new(:config => @redis_config, :size => options[:size])
      else
        ::Redis.new(@redis_config)
      end
    end

    def bootstrap(opts = {})
      return if @bootstrapped

      unless @logger = opts[:logger]
        @logger = Log4r::Logger.new("#{self.class.to_s.downcase.gsub('::', '-')}")
        @logger.add(Log4r::StdoutOutputter.new("flapjack"))
        @logger.add(Log4r::SyslogOutputter.new("flapjack"))
      end

      @redis_config = opts[:redis] || {}
      @config = opts[:config] || {}

      @should_quit = false

      @bootstrapped = true
    end

  end
end
