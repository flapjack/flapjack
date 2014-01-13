#!/usr/bin/env ruby

require 'eventmachine'
require 'em-synchrony'

require 'syslog'

require 'flapjack/configuration'
require 'flapjack/patches'
require 'flapjack/redis_pool'

require 'flapjack/logger'
require 'flapjack/pikelet'

module Flapjack

  class Coordinator

    def initialize(config)
      @config = config
      @redis_options = config.for_redis
      @pikelets = []

      @received_signals = []

      @logger = Flapjack::Logger.new("flapjack-coordinator", @config.all['logger'])
    end

    def start(options = {})
      @boot_time = Time.now

      EM.synchrony do
        setup_signals if options[:signals]

        begin
          add_pikelets(pikelets(@config.all))
          loop do
            while sig = @received_signals.shift do
              case sig
              when 'INT', 'TERM', 'QUIT'
                @exit_value = Signal.list[sig] + 128
                raise Interrupt
              when 'HUP'
                reload
              end
            end
            EM::Synchrony.sleep 0.25
          end
        rescue Exception => e
          unless e.is_a?(Interrupt)
            trace = e.backtrace.join("\n")
            @logger.fatal "#{e.class.name}\n#{e.message}\n#{trace}"
            @exit_value = 1
          end
          remove_pikelets(@pikelets)
          EM.stop
        end
      end

      Syslog.close if Syslog.opened?

      @exit_value
    end

    private

    def reload
      prev_pikelet_cfg = pikelets(@config.all)

      removed = []
      added = []
      ask_running = []

      cfg_filename = @config.filename
      @config = Flapjack::Configuration.new
      @config.load(cfg_filename)

      enabled_pikelet_cfg = pikelets(@config.all)

      (prev_pikelet_cfg.keys + enabled_pikelet_cfg.keys).each do |type|

        if prev_pikelet_cfg.keys.include?(type)
          if enabled_pikelet_cfg.keys.include?(type)
            ask_running << type
          else
            removed << type
          end
        elsif enabled_pikelet_cfg.keys.include?(type)
          added << type
        end

      end

      @pikelets.select {|pik| ask_running.include?(pik.type) }.each do |pik|
        # for sections previously there and still there, ask them
        # to make the config change; they will if they can, or will signal
        # restart is needed if not

        # reload() returns trinary value here; true means the change was made, false
        # means the pikelet needs to be restarted, nil means no change
        # was required
        next unless pik.reload(enabled_pikelet_cfg[pik.type]).is_a?(FalseClass)
        removed << pik.type
        added << pik.type
      end

      removed_pikelets = @pikelets.select {|pik| removed.include?(pik.type) }

      remove_pikelets(removed_pikelets)

      # is there a nicer way to only keep the parts of the hash with matching keys?
      added_pikelets = enabled_pikelet_cfg.select {|k, v| added.include?(k) }

      add_pikelets(added_pikelets)
    end

    # the global nature of this seems at odds with it calling stop
    # within a single coordinator instance. Coordinator is essentially
    # a singleton anyway...
    def setup_signals
      Kernel.trap('INT')    { @received_signals << 'INT' unless @received_signals.include?('INT') }
      Kernel.trap('TERM')   { @received_signals << 'TERM' unless @received_signals.include?('TERM') }
      unless RbConfig::CONFIG['host_os'] =~ /mswin|windows|cygwin/i
        Kernel.trap('QUIT') { @received_signals << 'QUIT' unless @received_signals.include?('QUIT') }
        Kernel.trap('HUP')  { @received_signals << 'HUP' unless @received_signals.include?('HUP') }
      end
    end

    # passed a hash with {PIKELET_TYPE => PIKELET_CFG, ...}
    def add_pikelets(pikelets_data = {})
      pikelets_data.each_pair do |type, cfg|
        next unless pikelet = Flapjack::Pikelet.create(type,
          :config => cfg, :redis_config => @redis_options,
          :boot_time => @boot_time)

        @pikelets << pikelet
        pikelet.start
      end
    end

    def remove_pikelets(piks, opts = {})
      piks.map(&:stop)

      loop do
        # only prints state changes, otherwise pikelets not closing promptly can
        # cause everything else to be spammy
        piks.each do |pik|
          old_status = pik.status
          pik.update_status
          status = pik.status
          next if old_status.eql?(status)
          @logger.info "#{pik.type}: #{old_status} -> #{status}"
        end

        if piks.any? {|p| p.status == 'stopping' }
          EM::Synchrony.sleep 0.25
        else
          @pikelets -= piks
          break
        end
      end
    end

    def pikelets(config_env)
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
