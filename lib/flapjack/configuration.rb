#!/usr/bin/env ruby


require 'yaml'

module Flapjack

  class Configuration

    def logger
      # @logger ||= TODO
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
        logger.error "TODO"
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

      config_env
    end

  end

end