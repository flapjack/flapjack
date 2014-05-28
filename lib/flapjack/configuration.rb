#!/usr/bin/env ruby

require 'yaml'
require 'logger'

module Flapjack

  class Configuration

    DEFAULT_CONFIG_PATH = '/etc/flapjack/flapjack_config.yaml'

    attr_reader :filename

    def initialize(opts = {})
      @logger = opts[:logger]
    end

    def all
      @config_env
    end

    def for_redis
      return unless @config_env

      redis_defaults = {'host' => 'localhost',
                        'port' => 6379,
                        'path' => nil,
                        'db'   => 0}

      @config_env['redis'] = {} unless @config_env.has_key?('redis')

      redis = @config_env['redis']
      redis_defaults.each_pair do |k,v|
        next if redis.has_key?(k) && redis[k] &&
          !(redis[k].is_a?(String) && redis[k].empty?)
        redis[k] = v
      end

      redis_path = (redis['path'] || nil)
      base_opts = {:db => (redis['db'] || 0)}
      base_opts[:driver] = redis['driver'] if redis['driver']
      redis_config = base_opts.merge(
        (redis_path ? { :path => redis_path } :
                      { :host => (redis['host'] || '127.0.0.1'),
                        :port => (redis['port'] || 6379)})
      )

      redis_config
    end

    def load(filename)
      @filename = nil
      @config_env = nil

      unless File.file?(filename)
        @logger.error "Could not find file '#{filename}'" if @logger
        return
      end

      unless defined?(FLAPJACK_ENV)
        @logger.error "Environment variable 'FLAPJACK_ENV' is not set, and no override supplied" if @logger
        return
      end

      config = YAML::load_file(filename)

      if config.nil?
        @logger.error "Could not load config file '#{filename}'" if @logger
        return
      end

      @config_env = config[FLAPJACK_ENV]

      if @config_env.nil?
        @logger.error "No config data for environment '#{FLAPJACK_ENV}' found in '#{filename}'" if @logger
        return
      end

      @filename = filename
    end

  end

end
