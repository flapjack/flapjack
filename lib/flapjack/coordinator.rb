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

    def initialize(config)
      @config = config
      @redis_options = config.for_redis
      @pikelets = []

      # TODO convert this to use flapjack-logger
      logger_name = "flapjack-coordinator"
      @logger = Log4r::Logger.new(logger_name)

      formatter = Log4r::PatternFormatter.new(:pattern => "%d [%l] :: #{logger_name} :: %m",
        :date_pattern => "%Y-%m-%dT%H:%M:%S%z")

      [Log4r::StdoutOutputter, Log4r::SyslogOutputter].each do |outp_klass|
        outp = outp_klass.new(logger_name)
        outp.formatter = formatter
        @logger.add(outp)
      end
    end

    def start(options = {})
      http_defs, non_http_defs = pikelets(@config.all).partition {|k, pd|
        Flapjack::Pikelet::Thin::PIKELET_TYPES.include?(k)
      }.map {|v| Hash[v] }

      p http_defs
      p non_http_defs

      return if http_defs.empty? && non_http_defs.empty?

      add_pikelets(http_defs) unless http_defs.empty?

      if non_http_defs.empty?
        setup_signals if options[:signals]
      else
        EM.synchrony do
          add_pikelets(non_http_defs)
          setup_signals if options[:signals]
        end
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
        # was required. Thin pikelets don't support this as they need to run
        # outside of the em-synchrony block.
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
      pikelets_data.each_pair do |type, cfg|
        next unless pikelet = Flapjack::Pikelet.create(type,
          :config => cfg, :redis_config => @redis_options)
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
      return {} unless config_env
      exec_cfg = config_env.has_key?('executive') && config_env['executive']['enabled'] ?
        {'executive' => config_env['executive']} :
        {}
      return exec_cfg unless config_env && config_env['gateways'] &&
        !config_env['gateways'].nil?
      exec_cfg.merge( config_env['gateways'].select {|k, v|
        Flapjack::Pikelet.is_pikelet?(k) && v['enabled']
      } )
    end

  end

end
