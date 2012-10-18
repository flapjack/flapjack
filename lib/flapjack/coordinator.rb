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

require 'flapjack/patches'

require 'flapjack/api'
require 'flapjack/daemonizing'
require 'flapjack/executive'
require 'flapjack/jabber'
require 'flapjack/oobetet'
require 'flapjack/pagerduty'
require 'flapjack/notification/email'
require 'flapjack/notification/sms'
require 'flapjack/redis_pool'
require 'flapjack/web'

module Flapjack

  class Coordinator

    include Flapjack::Daemonizable

    def initialize(config = {})
      @config = config
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
        setup(:signals => options[:signals])
      end
    end

    def after_daemonize
      setup(:signals => @signals)
    end

    def stop
      return if @stopping
      @stopping = true
      shutdown
    end

  private

    def setup(options = {})

      # FIXME: the following is currently repeated in flapjack-populator and
      # flapjack-nagios-receiver - move to a method in a module and include it
      redis_host = @config['redis']['host'] || '127.0.0.1'
      redis_port = @config['redis']['port'] || 6379
      redis_path = @config['redis']['path'] || nil
      redis_db   = @config['redis']['db']   || 0

      @redis_options = if redis_path
         { :db => redis_db, :path => redis_path }
      else
         { :db => redis_db, :host => redis_host, :port => redis_port }
      end

      EM.synchrony do
        @logger.debug "config keys: #{@config.keys}"

        pikelet_keys = ['executive', 'jabber_gateway', 'pagerduty_gateway',
                        'email_notifier', 'sms_notifier', 'web', 'api',
                        'oobetet']

        @config.keys.each do |pikelet_type|
          next unless pikelet_keys.include?(pikelet_type) &&
            @config[pikelet_type].is_a?(Hash) &&
            @config[pikelet_type]['enabled']
          @logger.debug "coordinator is now initialising the #{pikelet_type} pikelet"
          pikelet_cfg = @config[pikelet_type]

          case pikelet_type
          when 'executive', 'jabber_gateway', 'pagerduty_gateway', 'oobetet'
            build_pikelet(pikelet_type, pikelet_cfg)
          when 'web', 'api'
            build_thin_pikelet(pikelet_type, pikelet_cfg)
          when 'email_notifier', 'sms_notifier'
            build_resque_pikelet(pikelet_type, pikelet_cfg)
          end
        end

        setup_signals if @signals
      end

    end

    def setup_signals
      trap('INT')  { stop }
      trap('TERM') { stop }
      unless RUBY_PLATFORM =~ /mswin/
        trap('QUIT') { stop }
        # trap('HUP')  { }
      end
    end

    def build_pikelet(pikelet_type, pikelet_cfg)
      pikelet_class = case pikelet_type
      when 'executive'
        Flapjack::Executive
      when 'jabber_gateway'
        Flapjack::Jabber
      when 'pagerduty_gateway'
        Flapjack::Pagerduty
      when 'oobetet'
        Flapjack::Oobetet
      end
      return unless pikelet_class

      pikelet = pikelet_class.new
      f = Fiber.new {
        begin
          pikelet.bootstrap(:redis_config => @redis_options, :config => pikelet_cfg)
          pikelet.main
        rescue Exception => e
          trace = e.backtrace.join("\n")
          @logger.fatal "#{e.message}\n#{trace}"
          stop
        end
      }
      @pikelets << {:fiber => f, :class => pikelet_class, :instance => pikelet}
      f.resume
      @logger.debug "new fiber created for #{pikelet_type}"
    end

    def build_thin_pikelet(pikelet_type, pikelet_cfg)
      pikelet_class = case pikelet_type
      when 'web'
        Flapjack::Web
      when 'api'
        Flapjack::API
      end
      return unless pikelet_class

      pikelet_class.bootstrap(:config => pikelet_cfg, :redis_config => @redis_options)

      # only run once
      if ([Flapjack::Web, Flapjack::API] & @pikelets.collect {|p| p[:class]}).empty?
        Thin::Logging.silent = true
      end

      pikelet = Thin::Server.new('0.0.0.0', pikelet_class.instance_variable_get('@port'),
        pikelet_class, :signals => false)
      @pikelets << {:instance => pikelet, :class => pikelet_class}
      pikelet.start
      @logger.debug "new thin server instance started for #{pikelet_type}"
    end

    def build_resque_pikelet(pikelet_type, pikelet_cfg)
      pikelet_class = case pikelet_type
      when 'email_notifier'
        Flapjack::Notification::Email
      when 'sms_notifier'
        Flapjack::Notification::Sms
      end
      return unless pikelet_class

      pikelet_class.bootstrap(:config => pikelet_cfg)

      # set up connection pooling, stop resque errors (ensure that it's only
      # done once)
      if ([Flapjack::Notification::Email, Flapjack::Notification::Sms] &
        @pikelets.collect {|p| p[:class]}).empty?

        pool = Flapjack::RedisPool.new(:config => @redis_options)
        ::Resque.redis = pool
        pikelet_class.redis = pool
        ## NB: can override the default 'resque' namespace like this
        #::Resque.redis.namespace = 'flapjack'
      end

      pikelet_class.bootstrap(:config => pikelet_cfg)

      # TODO error if pikelet_cfg['queue'].nil?
      pikelet = EM::Resque::Worker.new(pikelet_cfg['queue'])
      # # Use these to debug the resque workers
      # pikelet.verbose = true
      # pikelet.very_verbose = true

      f = Fiber.new {
        begin
          pikelet.work(0.1)
        rescue Exception => e
          trace = e.backtrace.join("\n")
          @logger.fatal "#{e.message}\n#{trace}"
          stop
        end
      }
      pikelet_values = {:fiber => f, :class => pikelet_class, :instance => pikelet}
      pikelet_values[:pool] = pool if pool
      @pikelets << pikelet_values
      f.resume
      @logger.debug "new fiber created for #{pikelet_type}"
    end

    # only prints state changes, otherwise pikelets not closing promptly can
    # cause everything else to be spammy
    def health_check
      @pikelets.each do |pik|
        status = if pik[:instance].is_a?(Thin::Server)
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

        # would be neater if we could use something similar for the class << self
        # included pikelets as well
        if pik[:class].included_modules.include?(Flapjack::GenericPikelet)
          if pik[:fiber] && pik[:fiber].alive?
            pik[:instance].stop
            Fiber.new {
              # this needs to use a separate Redis connection from the pikelet's
              # one, as that's in the middle of its blpop
              r = Redis.new(@redis_options.merge(:driver => 'synchrony'))
              pik[:instance].add_shutdown_event(:redis => r)
              r.quit
            }.resume
          end
        elsif [Flapjack::Notification::Email,
          Flapjack::Notification::Sms].include?(pik[:class])
          # resque is polling, so we don't need a shutdown object
          pik[:instance].shutdown if pik[:fiber] && pik[:fiber].alive?
        elsif [Flapjack::Web, Flapjack::API].include?(pik[:class])
          # drop from this side, as HTTP keepalive etc. means browsers
          # keep connections alive for ages, and we'd be hanging around
          # waiting for them to drop
          pik[:instance].stop!
        end
      end

      Fiber.new {

        fibers = @pikelets.collect {|p| p[:fiber] }.compact
        thin_pikelets = @pikelets.select {|p|
          [Flapjack::Web, Flapjack::API].include?(p[:class])
        }

        loop do
          health_check

          if fibers.any?(&:alive?) || thin_pikelets.any?{|tp| !tp[:instance].backend.empty? }
            EM::Synchrony.sleep 0.25
          else

            @pikelets.each do |pik|
              if pik[:class].included_modules.include?(Flapjack::GenericPikelet)
                pik[:instance].cleanup
              elsif [Flapjack::Notification::Email,
                Flapjack::Notification::Sms,
                Flapjack::Web, Flapjack::API].include?(pik[:class])

                # TODO resque pool cleanup

                pik[:class].cleanup
              end
            end

            EM.stop
            break
          end
        end
      }.resume
    end

  end

end
