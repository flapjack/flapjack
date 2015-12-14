#!/usr/bin/env ruby

require 'monitor'
require 'syslog'

require 'zermelo'

require 'flapjack/configuration'
require 'flapjack/patches'

require 'flapjack/redis_proxy'

require 'flapjack/pikelet'

require 'flapjack/data/condition'

module Flapjack

  class Coordinator

    # states: :starting, :running, :reloading, :stopped

    def initialize(config)
      Thread.abort_on_exception = true

      ActiveSupport.use_standard_json_time_format = true
      ActiveSupport.time_precision = 0

      @exit_value = nil

      @config   = config
      @pikelets = []

      @received_signals = []

      @state = :starting
      @monitor = Monitor.new
      @monitor_cond = @monitor.new_cond

      # needs to be done per-thread
      cfg = @config.all
      Flapjack.configure_log('flapjack-coordinator', cfg.nil? ? {} : cfg['logger'])

      @reload = proc {
        @monitor.synchronize {
          @monitor_cond.wait_until { :running.eql?(@state) }
          @state = :reloading
          @monitor_cond.signal
        }
      }

      @shutdown = proc { |exit_val|
        @monitor.synchronize {
          @monitor_cond.wait_until { :running.eql?(@state) }
          @state = :stopping
          @exit_value = exit_val
          @monitor_cond.signal
        }
      }
    end

    def start(opts = {})
      # we can't block on the main thread, as signals interrupt that
      Thread.new do
        # needs to be done per-thread
        cfg = @config.all
        Flapjack.configure_log('flapjack-coordinator', cfg.nil? ? {} : cfg['logger'])

        @boot_time = Time.now

        Flapjack::RedisProxy.config = @config.for_redis

        pikelet_defs = pikelet_definitions(cfg)
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
          @state = :running
          @monitor_cond.wait_until { !(:running.eql?(@state)) }
          case @state
          when :reloading
            reload
            @state = :running
            @monitor_cond.signal
          when :stopping
            @pikelets.map(&:stop)
            @pikelets.clear
            @state = :stopped
            @monitor_cond.signal
          end
        }

      end.join

      @exit_value
    end

  private

    # the global nature of this seems at odds with it calling stop
    # within a single coordinator instance. Coordinator is essentially
    # a singleton anyway...
    def setup_signals
      Kernel.trap('INT')    { Thread.new { @shutdown.call(Signal.list['INT']) }.join }
      Kernel.trap('TERM')   { Thread.new { @shutdown.call(Signal.list['TERM']) }.join }
      unless RbConfig::CONFIG['host_os'] =~ /mswin|windows|cygwin/i
        Kernel.trap('HUP')  { Thread.new { @reload.call }.join }
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

    # NB: global config options (e.g. daemonize, pidfile,
    # logfile, redis options) won't be checked on reload.
    # should we do a full restart if some of these change?
    def reload
      # TODO refactor cfg load and key retrieval, consolidate with initial load
      prev_pikelet_cfg = pikelet_definitions(@config.all)

      @config.reload

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

  end

end
