#!/usr/bin/env ruby

require 'eventmachine'
require 'em-synchrony'

require 'flapjack/configuration'
require 'flapjack/patches'
require 'flapjack/executive'
require 'flapjack/redis_pool'

require 'flapjack/pikelet'
require 'flapjack/executive'

module Flapjack

  class Coordinator

    ALL_PIKELET_TYPES =
      [Flapjack::Pikelet::Generic,
       Flapjack::Pikelet::Resque,
       Flapjack::Pikelet::Thin].collect {|pk|

        pk::PIKELET_TYPES

      }.inject({}) {|m, h| m.merge(h)}

    def initialize(config)
      @config = config
      @redis_options = config.for_redis
      @pikelets = []

      @logger = Log4r::Logger.new("flapjack-coordinator")
      @logger.add(Log4r::StdoutOutputter.new("flapjack-coordinator"))
      @logger.add(Log4r::SyslogOutputter.new("flapjack-coordinator"))
    end

    def start(options = {})
      EM.synchrony do
        add_pikelets(pikelets(@config.all))
        setup_signals if options[:signals]
      end
    end

    def stop
      return if @stopping
      @stopping = true
      remove_pikelets(@pikelets, :shutdown => true)
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
      config.load(cfg_filename)

      enabled_pikelet_cfg = pikelets(@config.all)

      PIKELET_TYPES.values.each do |p_klass|

        if prev_pikelet_cfg.keys.include?(p_klass)
          if enabled_pikelet_cfg.keys.include?(p_klass)
            ask_running << p_klass
          else
            removed << p_klass
          end
        elsif enabled_pikelet_cfg.keys.include?(p_klass)
          added << p_klass
        end

      end

      @pikelets.select {|pik| ask_running.include?(pik.class) }.each do |pik|
        # for sections previously there and still there, ask them
        # to make the config change; they will if they can, or will signal
        # restart is needed if not

        # reload() returns trinary value here; true means the change was made, false
        # means the pikelet needs to be restarted, nil means no change
        # was required
        next unless pik.reload(pik_config).is_a?(FalseClass)
        removed << pik.class
      end

      removed_pikelets = @pikelets.select {|pik| removed.include?(pik.class) }

      remove_pikelets( removed_pikelets )
      add_pikelets(enabled_pikelet_cfg)
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
        # Kernel.trap('USR1')  { reload }
      end
    end

    # passed a hash with {PIKELET_TYPE => PIKELET_CFG, ...}
    def add_pikelets(pikelets_data = {})
      pikelets_data.each_pair do |type, cfg|
        pikelet = nil
        [Flapjack::Pikelet::Generic,
         Flapjack::Pikelet::Resque,
         Flapjack::Pikelet::Thin].each do |kl|
          # TODO find a better way of expressing this
          break if pikelet = kl.create(type, :config => cfg, :redis_config => @redis_options)
        end
        next unless pikelet
        @pikelets << pikelet
        pikelet.start
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
            status = pik.status(:check => true)
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
      return {} unless config_env
      exec_cfg = config_env.has_key?('executive') && config_env['executive']['enabled'] ?
        {'executive' => config_env['executive']} :
        {}
      return exec_cfg unless config_env && config_env['gateways'] &&
        !config_env['gateways'].nil?
      exec_cfg.merge(config_env['gateways'].inject({}) {|memo, (k, v)|
        memo[k] = v if ALL_PIKELET_TYPES.has_key?(k) && v['enabled']
        memo
      })
    end

  end

end
