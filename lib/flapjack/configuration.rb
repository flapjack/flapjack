#!/usr/bin/env ruby

require 'toml'
require 'logger'
require 'active_support/core_ext/hash/indifferent_access'

module Flapjack

  class Configuration

    DEFAULT_CONFIG_PATH = '/etc/flapjack/flapjack_config.toml'

    attr_reader :filename

    def initialize(opts = {})
      @logger = opts[:logger]
    end

    def all
      @config
    end

    def for_redis
      return unless @config

      redis_defaults = {'host'   => '127.0.0.1',
                        'port'   => 6379,
                        'path'   => nil,
                        'db'     => 0}

      @config['redis'] = {} unless @config.has_key?('redis')

      redis = @config['redis']
      redis_defaults.each_pair do |k,v|
        next if redis.has_key?(k) && redis[k] &&
          !(redis[k].is_a?(String) && redis[k].empty?)
        redis[k] = v
      end

      redis_path = (redis['path'] || nil)
      base_opts = HashWithIndifferentAccess.new({ :db => (redis['db'] || 0) })
      base_opts[:driver] = redis['driver'] if redis['driver']
      redis_config = base_opts.merge(
        (redis_path ? { :path => redis_path } :
                      { :host => (redis['host'] || '127.0.0.1'),
                        :port => (redis['port'] || 6379)})
      )

      redis_config[:password] = redis["password"] if redis["password"]

      redis_config
    end

    def load(filename)
      @filename = nil
      @config = nil

      unless File.file?(filename)
        @logger.error "Could not find file '#{filename}'" if @logger
        return
      end

      config = TOML.load_file(filename)
      
      if config.nil?
        @logger.error "Could not load config file '#{filename}'" if @logger
        return
      end
      
      config = HashWithIndifferentAccess.new(config)
      
      @config = config

      @filename = filename
    end

  end

end
