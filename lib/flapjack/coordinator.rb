#!/usr/bin/env ruby

require 'eventmachine'
# the redis/synchrony gems need to be required in this particular order, see
# the redis-rb README for details
require 'hiredis'
require 'em-synchrony'
require 'redis/connection/synchrony'
require 'redis'
require 'em-resque'
require 'em-resque/worker'
require 'thin'

require 'flapjack/configuration'
require 'flapjack/patches'
require 'flapjack/daemonizing'
require 'flapjack/executive'
require 'flapjack/redis_pool'

require 'flapjack/gateways/api'
require 'flapjack/gateways/jabber'
require 'flapjack/gateways/oobetet'
require 'flapjack/gateways/pagerduty'
require 'flapjack/gateways/email'
require 'flapjack/gateways/sms_messagenet'
require 'flapjack/gateways/web'

module Flapjack

  class Coordinator

    include Flapjack::Daemonizable

    def initialize(config)
      @config = config
      @redis_options = config.for_redis
      @pikelets = []

      @logger = Log4r::Logger.new("flapjack-coordinator")
      @logger.add(Log4r::StdoutOutputter.new("flapjack-coordinator"))
      @logger.add(Log4r::SyslogOutputter.new("flapjack-coordinator"))
    end

    def start(options = {})
      @signals = options[:signals]
      if options[:daemonize]
        @signals = options[:signals]
        daemonize
      else
        run(:signals => options[:signals])
      end
    end

    def after_daemonize
      run(:signals => @signals)
    end

    def stop
      return if @stopping
      @stopping = true
      shutdown
    end

  private

    # map from config key to gateway class
    GATEWAY_TYPES = {'jabber'         => Flapjack::Gateways::Jabber,
                     'pagerduty'      => Flapjack::Gateways::Pagerduty,
                     'oobetet'        => Flapjack::Gateways::Oobetet,

                     'web'            => Flapjack::Gateways::Web,
                     'api'            => Flapjack::Gateways::API,

                     'email'          => Flapjack::Gateways::Email,
                     'sms_messagenet' => Flapjack::Gateways::SmsMessagenet}

    def run(options = {})

      EM.synchrony do
        @logger.debug "config executive key found" if @config.for_executive
        all = @config.all
        gateway_keys = (all && all['gateways']) ? all['gateways'].keys : []
        @logger.debug "config gateway keys: #{gateway_keys}"

        (['executive'] + gateway_keys).each do |pikelet_type|
          build_pikelet(pikelet_type)
        end

        setup_signals if @signals
      end

    end

    # the global nature of this seems at odds with it calling stop
    # within a single coordinator instance. Coordinator is essentially
    # a singleton anyway...
    def setup_signals
      Kernel.trap('INT')  { stop }
      Kernel.trap('TERM') { stop }
      unless RbConfig::CONFIG['host_os'] =~ /mswin|windows|cygwin/i
        Kernel.trap('QUIT') { stop }
        # Kernel.trap('HUP')  { }
      end
    end

    def build_pikelet(pikelet_type)
      if 'executive'.eql?(pikelet_type)
        pikelet_cfg = @config.for_executive
        pikelet_class = Flapjack::Executive
      elsif GATEWAY_TYPES.keys.include?(pikelet_type)
        pikelet_cfg = @config.for_gateway(pikelet_type)
        pikelet_class = GATEWAY_TYPES[pikelet_type]
      else
        pikelet_cfg = nil
        pikelet_class = nil
      end

      return unless pikelet_cfg.is_a?(Hash) && pikelet_cfg['enabled'] &&
        pikelet_class

      @logger.debug "coordinator is now initialising the #{pikelet_type} pikelet"

      inc_mod = pikelet_class.included_modules
      ext_mod = extended_modules(pikelet_class)

      pikelet = nil
      fiber = nil

      if inc_mod.include?(Flapjack::GenericPikelet)
        pikelet = pikelet_class.new
        pikelet.bootstrap(:config => pikelet_cfg, :redis_config => @redis_options)
      else
        pikelet_class.bootstrap(:config => pikelet_cfg, :redis_config => @redis_options)

        if ext_mod.include?(Flapjack::Gateways::Thin)

          unless @thin_silenced
            Thin::Logging.silent = true
            @thin_silenced = true
          end

          pikelet = Thin::Server.new('0.0.0.0',
                      pikelet_class.instance_variable_get('@port'),
                      pikelet_class, :signals => false)

        elsif ext_mod.include?(Flapjack::Gateways::Resque)

          # set up connection pooling, stop resque errors
          unless @resque_pool
            @resque_pool = Flapjack::RedisPool.new(:config => @redis_options)
            ::Resque.redis = @resque_pool
            ## NB: can override the default 'resque' namespace like this
            #::Resque.redis.namespace = 'flapjack'
          end

          # TODO error if pikelet_cfg['queue'].nil?
          pikelet = EM::Resque::Worker.new(pikelet_cfg['queue'])
          # # Use these to debug the resque workers
          # pikelet.verbose = true
          # pikelet.very_verbose = true
        end

      end

      pikelet_info = {:class => pikelet_class, :instance => pikelet}

      if inc_mod.include?(Flapjack::GenericPikelet) ||
        ext_mod.include?(Flapjack::Gateways::Resque)

        fiber = Fiber.new {
          begin
            # Can't use local inc_mod/ext_mod variables in the new fiber
            if pikelet.is_a?(Flapjack::GenericPikelet)
              pikelet.main
            elsif extended_modules(pikelet_class).include?(Flapjack::Gateways::Resque)
              pikelet.work(0.1)
            end
          rescue Exception => e
            trace = e.backtrace.join("\n")
            @logger.fatal "#{e.message}\n#{trace}"
            stop
          end
        }

        pikelet_info[:fiber] = fiber
        fiber.resume
        @logger.debug "new fiber created for #{pikelet_type}"
      elsif ext_mod.include?(Flapjack::Gateways::Thin)
        pikelet.start
        @logger.debug "new thin server instance started for #{pikelet_type}"
      end

      @pikelets << pikelet_info
    end

    # only prints state changes, otherwise pikelets not closing promptly can
    # cause everything else to be spammy
    def health_check
      @pikelets.each do |pik|
        status = if extended_modules(pik[:class]).include?(Flapjack::Gateways::Thin)
          pik[:instance].backend.size > 0 ? 'running' : 'stopped'
        elsif pik[:fiber]
          pik[:fiber].alive? ? 'running' : 'stopped'
        end
        next if pik.has_key?(:status) && pik[:status].eql?(status)
        @logger.info "#{pik[:class].name}: #{status}"
        pik[:status] = status
      end
    end

    def shutdown
      @pikelets.each do |pik|

        pik_inst = pik[:instance]
        ext_mod  = extended_modules(pik[:class])

        # would be neater if we could use something similar for the class << self
        # included pikelets as well
        if pik_inst.is_a?(Flapjack::GenericPikelet)
          if pik[:fiber] && pik[:fiber].alive?
            pik_inst.stop
            Fiber.new {
              # this needs to use a separate Redis connection from the pikelet's
              # one, as that's in the middle of its blpop
              r = Redis.new(@redis_options.merge(:driver => 'synchrony'))
              pik_inst.add_shutdown_event(:redis => r)
              r.quit
            }.resume
          end
        elsif ext_mod.include?(Flapjack::Gateways::Resque)
          # resque is polling, so we don't need a shutdown object
          pik_inst.shutdown if pik[:fiber] && pik[:fiber].alive?
        elsif ext_mod.include?(Flapjack::Gateways::Thin)
          # drop from this side, as HTTP keepalive etc. means browsers
          # keep connections alive for ages, and we'd be hanging around
          # waiting for them to drop
          pik_inst.stop!
        end
      end

      Fiber.new {

        loop do
          health_check

          if @pikelets.any? {|p| p[:status] == 'running'}
            EM::Synchrony.sleep 0.25
          else
            @resque_pool.empty! if @resque_pool

            @pikelets.each do |pik|

              pik_inst = pik[:instance]
              ext_mod = extended_modules(pik[:class])

              if pik_inst.is_a?(Flapjack::GenericPikelet)

                pik_inst.cleanup

              elsif [Flapjack::Gateways::Resque, Flapjack::Gateways::Thin].any?{|fp|
                ext_mod.include?(fp)
              }

                pik[:class].cleanup

              end
            end

            EM.stop
            break
          end
        end
      }.resume
    end

    def extended_modules(klass)
      (class << klass; self; end).included_modules
    end

  end

end
