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
    attr_accessor :logger, :config, :redis

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
      @redis_config =  opts.delete(:redis_config) || {}
      @should_quit = false

      orig_bootstrap(opts)
    end

    def build_redis_connection_pool(options)
      options ||= {}
      return unless @bootstrapped
      if defined?(FLAPJACK_ENV) && 'test'.eql?(FLAPJACK_ENV)
        ::Redis.new(@redis_config.merge(:driver => 'ruby'))
      else
        Flapjack::RedisPool.new(:config => @redis_config, :size => (options[:size] || 5))
      end
    end

    def cleanup
    end

  end

  module ResquePikelet
    include Flapjack::Pikelet

    def cleanup
      @redis.empty!
    end
  end

  module ThinPikelet
    include Flapjack::Pikelet

    attr_accessor :port

    alias_method :orig_bootstrap, :bootstrap

    def bootstrap(opts = {})
      return if @bootstrapped

      config = opts[:config]
      redis_config = opts.delete(:redis_config) || {}

      @port = config['port'] ? config['port'].to_i : nil
      @port = 3001 if (@port.nil? || @port <= 0 || @port > 65535)

      redis_size = opts.delete(:redis_size)

      @redis = if defined?(FLAPJACK_ENV) && 'test'.eql?(FLAPJACK_ENV)
        ::Redis.new(redis_config.merge(:driver => 'ruby'))
      else
        Flapjack::RedisPool.new(:config => redis_config, :size => redis_size)
      end

      orig_bootstrap(opts)
    end

    def cleanup
      @redis.empty! if @redis
    end
  end
end
