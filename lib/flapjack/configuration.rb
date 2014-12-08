#!/usr/bin/env ruby

require 'toml'
require 'logger'
require 'active_support/core_ext/hash/indifferent_access'

module Flapjack

  class Configuration

    # DEFAULT_CONFIG_PATH = '/etc/flapjack/flapjack_config.toml'

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

    def load(file_pattern)
      @file_pattern = nil
      @config = nil

      config_file_names = Dir.glob(file_pattern)

      config_file_names.each { |f| raise "#{f} looks like a YAML file. Flapjack v2 config files are now in TOML, see flapjack.io/docs/2.x/configuration" if f.end_with?('.yaml') }

      if config_file_names.nil?
        @logger.error(
          "Could not load config files using file_pattern '#{file_pattern}'"
        ) if @logger
        return
      end
      
      config = config_file_names.inject({}) do |config, file_name|
        config.merge!(TOML.load_file(file_name)) do |key, old_val, new_val|
          if old_val != new_val 
            @logger.error("Duplicate configuration setting #{key} in #{file_name}") if @logger
            break   
          else
            new_val
          end    
        end  
      end
      
      if config.nil? || config.empty?
        @logger.error(
          "Could not load config files using file_pattern '#{file_pattern}'"
        ) if @logger
        return
      end

      config = HashWithIndifferentAccess.new(config)

      @config = config

      @file_pattern = file_pattern
    end
    
    def reload
      unless @file_pattern
        @logger.error "Cannot reload, config file_pattern not set." if @logger
        return
      end
      
      load(@file_pattern)  
    end 
    

  end

end
