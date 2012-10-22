#!/usr/bin/env ruby

require 'yaml'
require 'logger'

module Flapjack

  class Configuration

    def initialize(opts = {})
      @logger = opts[:logger]
      unless @logger
        @logger       = Logger.new(STDOUT)
        @logger.level = Logger::ERROR
      end
    end

    def logger
      @logger
    end

    def load(filename)
      unless File.file?(filename)
        logger.error "Could not find file '#{filename}'"
        return
      end

      unless defined?(FLAPJACK_ENV)
        logger.error "Environment variable 'FLAPJACK_ENV' is not set"
        return
      end

      config = YAML::load_file(filename)

      if config.nil?
        logger.error "Could not load config file '#{filename}'"
        return
      end

      config_env = config[FLAPJACK_ENV]

      if config_env.nil?
        logger.error "No config data for environment '#{FLAPJACK_ENV}' found in '#{filename}'"
        return
      end

      redis_defaults = {'host' => 'localhost',
                        'port' => 6379,
                        'path' => nil,
                        'db'   => 0}

      config_env['redis'] = {} unless config_env.has_key?('redis')
      redis_defaults.each_pair do |k,v|
        next if config_env['redis'].has_key?(k) && (config_env['redis'][k] &&
          !(config_env['redis'][k].is_a?(String) && config_env['redis'][k].empty?))
        config_env['redis'][k] = v
      end

      redis_path = (config_env['redis']['path'] || nil)
      base_opts = {:db => (config_env['redis']['db'] || 0)
      redis_config = base_opts.merge(
        redis_path ? { :path => redis_path } :
                     { :host => (config_env['redis']['host'] || '127.0.0.1'),
                       :port => (@config_env['redis']['port'] || 6379)}
      )

      return config_env, redis_config
    end

  end

end
