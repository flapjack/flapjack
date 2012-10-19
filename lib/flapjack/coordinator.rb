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
        daemonize
      else
        setup
      end
    end

    def after_daemonize
      setup
    end

    def stop
      shutdown
    end

  private

    def setup

      # FIXME: the following is currently repeated in flapjack-populator and
      # flapjack-nagios-receiver - move to a method in a module and include it
      redis_host = @config['redis']['host'] || '127.0.0.1'
      redis_port = @config['redis']['port'] || 6379
      redis_path = @config['redis']['path'] || nil
      redis_db   = @config['redis']['db']   || 0

      if redis_path
        @redis_options = { :db => redis_db, :path => redis_path }
      else
        @redis_options = { :db => redis_db, :host => redis_host, :port => redis_port }
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
          pikelet.bootstrap(:redis => @redis_options, :config => pikelet_cfg)
          pikelet.main
        rescue Exception => e
          trace = e.backtrace.join("\n")
          @logger.fatal "#{e.message}\n#{trace}"
          stop
        end
      }
      @pikelets << {:fiber => f, :type => pikelet_type, :instance => pikelet}
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

      port = nil
      if pikelet_cfg['port']
        port = pikelet_cfg['port'].to_i
      end

      port = 3001 if (port.nil? || port <= 0 || port > 65535)

      pikelet_class.class_variable_set('@@redis',
        Flapjack::RedisPool.new(:config => @redis_options))

      Thin::Logging.silent = true

      pikelet = Thin::Server.new('0.0.0.0', port, pikelet_class, :signals => false)
      @pikelets << {:instance => pikelet, :type => pikelet_type}
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

      # set up connection pooling, stop resque errors (ensure that it's only
      # done once)
      @resque_pool = nil
      if (['email_notifier', 'sms_notifier'] & @pikelets.collect {|p| p[:type]}).empty?
        pool = Flapjack::RedisPool.new(:config => @redis_options)
        ::Resque.redis = pool
        @resque_pool = pool
        ## NB: can override the default 'resque' namespace like this
        #::Resque.redis.namespace = 'flapjack'
      end

      # See https://github.com/mikel/mail/blob/master/lib/mail/mail.rb#L53
      # & https://github.com/mikel/mail/blob/master/spec/mail/configuration_spec.rb
      # for details of configuring mail gem. defaults to SMTP, localhost, port 25

      if pikelet_type.eql?('email_notifier')
        smtp_config = {}

        if pikelet_cfg['smtp_config']
          smtp_config = pikelet_cfg['smtp_config'].keys.inject({}) do |ret,obj|
            ret[obj.to_sym] = pikelet_cfg['smtp_config'][obj]
            ret
          end
        end

        Mail.defaults {
          delivery_method :smtp, {:enable_starttls_auto => false}.merge(smtp_config)
        }
      end

      pikelet_class.class_variable_set('@@config', pikelet_cfg)

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
      @pikelets << {:fiber => f, :type => pikelet_type, :instance => pikelet}
      f.resume
      @logger.debug "new fiber created for #{pikelet_type}"
    end

    # # TODO rewrite to be less spammy -- print only initial state and changes
    # def health_check
    #   @pikelets.each do |pik|
    #     if pik[:instance].is_a?(Thin::Server)
    #       s = pik[:instance].backend.size
    #       @logger.debug "thin on port #{pik[:instance].port} - #{s} connections"
    #     elsif pik[:fiber]
    #       @logger.debug "#{pik[:type]}: #{pik[:fiber].alive? ? 'alive' : 'dead'}"
    #     end
    #   end
    # end

    # TODO whem merged with other changes, have this check pik[:class] instead,
    # makes tests neater
    def shutdown
      @pikelets.each do |pik|
        case pik[:instance]
        when Flapjack::Executive, Flapjack::Jabber, Flapjack::Pagerduty
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
        when EM::Resque::Worker
          # resque is polling, so we don't need a shutdown object
          pik[:instance].shutdown if pik[:fiber] && pik[:fiber].alive?
        when Thin::Server # web, api
          # drop from this side, as HTTP keepalive etc. means browsers
          # keep connections alive for ages, and we'd be hanging around
          # waiting for them to drop
          pik[:instance].stop!
        end
      end

      fibers = @pikelets.collect {|p| p[:fiber] }.compact
      thin_pikelets = @pikelets.collect {|p| p[:instance]}.select {|i| i.is_a?(Thin::Server) }

      Fiber.new {
        loop do
          # health_check
          if fibers.any?(&:alive?) || thin_pikelets.any?{|tp| !tp.backend.empty? }
            EM::Synchrony.sleep 0.25
          else
            @resque_pool.empty! if @resque_pool

            [Flapjack::Web, Flapjack::API].each do |klass|
              next unless klass.class_variable_defined?('@@redis') &&
                redis = klass.class_variable_get('@@redis')
              redis.empty!
            end

            EM.stop
            break
          end
        end
      }.resume
    end

  end

end
