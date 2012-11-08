#!/usr/bin/env ruby

require 'yaml'
require 'logger'

require 'flapjack/executive'

require 'flapjack/gateways/api'
require 'flapjack/gateways/jabber'
require 'flapjack/gateways/oobetet'
require 'flapjack/gateways/pagerduty'
require 'flapjack/gateways/email'
require 'flapjack/gateways/sms'
require 'flapjack/gateways/web'

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

    # TODO reduce/remove the use of this, just access parts
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
      redis_config = base_opts.merge(
        (redis_path ? { :path => redis_path } :
                      { :host => (redis['host'] || '127.0.0.1'),
                        :port => (redis['port'] || 6379)})
      )

      redis_config
    end

    PIKELET_TYPES = {'executive'  => Flapjack::Executive}

    GATEWAY_TYPES = {'web'        => Flapjack::Gateways::Web,
                     'api'        => Flapjack::Gateways::API,
                     'jabber'     => Flapjack::Gateways::Jabber,
                     'pagerduty'  => Flapjack::Gateways::Pagerduty,
                     'oobetet'    => Flapjack::Gateways::Oobetet,
                     'email'      => Flapjack::Gateways::Email,
                     'sms'        => Flapjack::Gateways::Sms}

    def pikelets
      return {} unless @config_env
      @config_env.inject({}) {|memo, (k, v)|
        if klass = PIKELET_TYPES[k]
          memo[klass] = v
        end
        memo
      }
    end

    def gateways
      return {} unless @config_env && @config_env['gateways'] &&
        !@config_env['gateways'].nil?
      @config_env['gateways'].inject({}) {|memo, (k, v)|
        if klass = GATEWAY_TYPES[k]
          memo[klass] = v
        end
        memo
      }
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

      @config_env = config[FLAPJACK_ENV]

      if @config_env.nil?
        logger.error "No config data for environment '#{FLAPJACK_ENV}' found in '#{filename}'"
        return
      end
    end

  end

end
