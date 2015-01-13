#!/usr/bin/env ruby

require 'toml'
require 'active_support/core_ext/hash/indifferent_access'

module Flapjack
  class Configuration

    attr_reader :filename

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
        next if redis.has_key?(k) && !redis[k].nil? &&
          !(redis[k].is_a?(String) && redis[k].empty?)
        redis[k] = v
      end

      redis_path = (redis['path'] || nil)
      base_opts = HashWithIndifferentAccess.new({ :db => (redis['db'] || 0) })
      base_opts[:driver] = redis['driver'] unless redis['driver'].nil?
      redis_config = base_opts.merge(
        (redis_path ? { :path => redis_path } :
                      { :host => (redis['host'] || '127.0.0.1'),
                        :port => (redis['port'] || 6379)})
      )

      redis_config[:password] = redis["password"] if redis["password"]

      redis_config
    end

    def load(file_pattern)
      @file_pattern = nil
      @config = nil

      config_file_names = Dir.glob(file_pattern)

      if config_file_names.nil?
        Flapjack.logger.error {
          "Could not load config files using file_pattern '#{file_pattern}'"
        }
        return
      end

      yaml_file = config_file_names.detect {|f| f.end_with?('.yaml') }

      unless yaml_file.nil?
        raise "#{yaml_file} looks like a YAML file. Flapjack v2 config files are now in TOML, " +
          "see flapjack.io/docs/2.x/configuration"
      end

      config = config_file_names.inject({}) do |config, file_name|
        config.merge!(TOML.load_file(file_name)) do |key, old_val, new_val|
          if old_val != new_val
            Flapjack.logger.error {
              "Duplicate configuration setting #{key} in #{file_name}"
            }
            break
          else
            new_val
          end
        end
      end

      if config.nil? || config.empty?
        Flapjack.logger.error {
          "Could not load config files using file_pattern '#{file_pattern}'"
        }
        return
      end

      @config = HashWithIndifferentAccess.new(config)

      @file_pattern = file_pattern
    end

    def reload
      if @file_pattern.nil?
        Flapjack.logger.error "Cannot reload, config file_pattern not set."
        return
      end

      load(@file_pattern)
    end
  end
end
