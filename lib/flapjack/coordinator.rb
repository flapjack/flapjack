#!/usr/bin/env ruby

require 'flapjack/configuration'
require 'flapjack/patches'
require 'flapjack/pikelet'

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
      pikelet_defs = pikelet_definitions(@config.all)
      return if pikelet_defs.empty?

      create_pikelets(pikelet_defs).each do |pik|
        @pikelets << pik
        pik.start
      end

      setup_signals if options[:signals]

      @main_thread = Thread.current
      @main_thread.sleep
    end

    def stop
      return if @stopping
      @stopping = true
      stop_pikelets(@pikelets)
      @pikelets.clear
      @main_thread.wakeup if @main_thread
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
      stop_pikelets(pikelets_to_remove)
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
      Kernel.trap('INT')  { stop }
      Kernel.trap('TERM') { stop }
      unless RbConfig::CONFIG['host_os'] =~ /mswin|windows|cygwin/i
        Kernel.trap('QUIT') { stop }
        Kernel.trap('HUP')  { reload }
      end
    end

    # passed a hash with {PIKELET_TYPE => PIKELET_CFG, ...}
    # returns unstarted pikelet instances.
    def create_pikelets(pikelets_data = {})
      pikelets_data.inject([]) do |memo, (type, cfg)|
        pikelet = Flapjack::Pikelet.create(type, :config => cfg,
                                           :redis_config => @redis_options)
        memo << pikelet if pikelet
        memo
      end
    end

    def stop_pikelets(pikelets, opts = {})
      pikelets.map(&:stop)
      pikelets.map(&:block_until_finished)
    end

    def pikelet_definitions(config_env)
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
