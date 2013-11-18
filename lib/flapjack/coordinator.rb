#!/usr/bin/env ruby

require 'monitor'
require 'syslog'

require 'sandstorm'

require 'flapjack/configuration'
require 'flapjack/patches'

require 'flapjack/redis_proxy'

require 'flapjack/logger'
require 'flapjack/pikelet'

module Flapjack

  class Coordinator

    def initialize(config)
      Thread.abort_on_exception = true

      @config       = config
      @pikelets     = []

      @monitor = Monitor.new
      @shutdown_cond = @monitor.new_cond

      @shutdown = proc {
        @monitor.synchronize {
          @shutdown_cond.signal
        }
      }

      @logger = Flapjack::Logger.new("flapjack-coordinator", @config.all['logger'])
    end

    def start(opts = {})
      @boot_time = Time.now

      Flapjack::RedisProxy.config = @config.for_redis

      pikelet_defs = pikelet_definitions(@config.all)
      return if pikelet_defs.empty?

      create_pikelets(pikelet_defs).each do |pik|
        @pikelets << pik
      end

      @pikelets.each do |pik|
        pik.start
      end

      setup_signals if opts[:signals]

      # block this thread until 'stop' has been called, and
      # all pikelets have been stopped
      @monitor.synchronize {
        @shutdown_cond.wait
        @pikelets.map(&:stop)
        @pikelets.clear
      }

      @exit_value
    end

    def stop(value = 0)
      return unless @exit_value.nil?
      @exit_value = value
      # a new thread is required to avoid deadlock errors; signal
      # handler runs by jumping into main thread
      Thread.new do
        Thread.current.abort_on_exception = true
        @monitor.synchronize { @shutdown_cond.signal }
      end
      @exit_value
    end

    # NB: global config options (e.g. daemonize, pidfile,
    # logfile, redis options) won't be checked on reload.
    # should we do a full restart if some of these change?
    def reload
      # TODO refactor cfg load and key retrieval, consolidate with initial load
      prev_pikelet_cfg = pikelet_definitions(@config.all)

      cfg_filename = @config.filename
      @config = Flapjack::Configuration.new
      @config.load(cfg_filename)

      current_pikelet_cfg = pikelet_definitions(@config.all)

      prev_keys    = prev_pikelet_cfg.keys
      current_keys = current_pikelet_cfg.keys

      removed     = prev_keys - current_keys
      added       = current_keys - prev_keys
      ask_running = current_keys - (added + removed)

      # for sections previously there and still there, ask them
      # to make the config change; they will if they can, or will signal
      # restart is needed if not
      # reload() returns trinary value here; true means the change was made, false
      # means the pikelet needs to be restarted, nil means no change
      # was required.
      ask_running.each do |ask_key|
        next unless pikelet = @pikelets.detect {|pik| ask_key == pik.type}

        if pikelet.reload(current_pikelet_cfg[pikelet.type]).is_a?(FalseClass)
          removed << pikelet.type
          added << pikelet.type
        end
      end

      pikelets_to_remove = @pikelets.select{|pik| removed.include?(pik.type) }
      pikelets_to_remove.map(&:stop)
      @pikelets -= pikelets_to_remove

      added_defs = current_pikelet_cfg.select {|k, v| added.include?(k) }

      create_pikelets(added_defs).each do |pik|
        @pikelets << pik
        pik.start
      end
    end

  private

    # the global nature of this seems at odds with it calling stop
    # within a single coordinator instance. Coordinator is essentially
    # a singleton anyway...
    def setup_signals
      Kernel.trap('INT')  { stop(Signal.list['INT']) }
      Kernel.trap('TERM') { stop(Signal.list['TERM']) }
      unless RbConfig::CONFIG['host_os'] =~ /mswin|windows|cygwin/i
        Kernel.trap('QUIT') { stop(Signal.list['QUIT']) }
        Kernel.trap('HUP')  { reload }
      end
    end

    # passed a hash with {PIKELET_TYPE => PIKELET_CFG, ...}
    # returns unstarted pikelet instances.
    def create_pikelets(pikelets_data = {})
      pikelets_data.inject([]) do |memo, (type, cfg)|
        pikelets = Flapjack::Pikelet.create(type, @shutdown, :config => cfg,
                                            :boot_time => @boot_time)
        memo += pikelets
        memo
      end
    end

    def pikelet_definitions(config_env)
       config = {}
      return config unless config_env

      # backwards-compatible with config file for previous 'executive' pikelet
      exec_cfg = nil
      if config_env.has_key?('executive') && config_env['executive']['enabled']
        exec_cfg = config_env['executive']
      end
      ['processor', 'notifier'].each do |k|
        if exec_cfg
          if config_env.has_key?(k)
            # need to allow for new config fields to override old settings if both present
            merged = exec_cfg.merge(config_env[k])
            config.update(k => merged) if merged['enabled']
          else
            config.update(k => exec_cfg)
          end
        else
          next unless (config_env.has_key?(k) && config_env[k]['enabled'])
          config.update(k => config_env[k])
        end
      end

      return config unless config_env && config_env['gateways'] &&
        !config_env['gateways'].nil?
      config.merge( config_env['gateways'].select {|k, v|
        Flapjack::Pikelet.is_pikelet?(k) && v['enabled']
      } )
    end

  end

end
