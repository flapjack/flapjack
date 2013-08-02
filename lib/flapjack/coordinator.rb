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

      @logger = Flapjack::Logger.new("flapjack-coordinator")
    end

    def start(options = {})
      @boot_time = Time.now

      EM.synchrony do
        setup_signals if options[:signals]
        add_pikelets(pikelets(@config.all))
      end
    end

    def stop
      return if @stopping
      @stopping = true
      remove_pikelets(@pikelets, :shutdown => true)
      # Syslog.close if Syslog.opened? # TODO revisit in threading branch
    end

    # NB: global config options (e.g. daemonize, pidfile,
    # logfile, redis options) won't be checked on reload.
    # should we do a full restart if some of these change?
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

      # puts "removed"
      # p removed

      # puts "added"
      # p added

      removed_pikelets = @pikelets.select {|pik| removed.include?(pik.type) }

      # puts "removed pikelets"
      # p removed_pikelets

      remove_pikelets(removed_pikelets)

      # is there a nicer way to only keep the parts of the hash with matching keys?
      added_pikelets = enabled_pikelet_cfg.select {|k, v| added.include?(k) }

      # puts "added pikelet configs"
      # p added_pikelets

      add_pikelets(added_pikelets)
    end

  private

    # the global nature of this seems at odds with it calling stop
    # within a single coordinator instance. Coordinator is essentially
    # a singleton anyway...
    def setup_signals
      Kernel.trap('INT')  { stop }
      Kernel.trap('TERM') { stop }
      unless RbConfig::CONFIG['host_os'] =~ /mswin|windows|cygwin/i
        Kernel.trap('QUIT') { stop }
        Kernel.trap('HUP')  { reload }
      end
    end

    # passed a hash with {PIKELET_TYPE => PIKELET_CFG, ...}
    def add_pikelets(pikelets_data = {})
      start_piks = []
      pikelets_data.each_pair do |type, cfg|
        next unless pikelet = Flapjack::Pikelet.create(type,
          :config => cfg, :redis_config => @redis_options, :boot_time => @boot_time, :coordinator => self)
        start_piks << pikelet
        @pikelets << pikelet
      end
      begin
        start_piks.each {|pik| pik.start }
      rescue Exception => e
        trace = e.backtrace.join("\n")
        @logger.fatal "#{e.class.name}\n#{e.message}\n#{trace}"
        stop
      end
    end

    def remove_pikelets(piks, opts = {})
      Fiber.new {
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
            EM.stop if opts[:shutdown]
            @pikelets -= piks
            break
          end
        end
      }.resume
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
