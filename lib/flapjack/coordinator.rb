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
require 'flapjack/pagerduty'
require 'flapjack/notification/email'
require 'flapjack/notification/sms'
require 'flapjack/web'

module Flapjack

  class Coordinator

    include Flapjack::Daemonizable

    def initialize(config = {})
      @config = config
      @pikelets = []
      @pikelet_fibers = {}

      @logger = Log4r::Logger.new("flapjack-coordinator")
      @logger.add(Log4r::StdoutOutputter.new("flapjack-coordinator"))
      @logger.add(Log4r::SyslogOutputter.new("flapjack-coordinator"))
    end

    def start(options = {})
      # FIXME raise error if config not set, or empty

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
                        'email_notifier', 'sms_notifier', 'web', 'api']

        @config.keys.each do |pikelet_type|
          next unless pikelet_keys.include?(pikelet_type) && 
            @config[pikelet_type].is_a?(Hash) &&
            @config[pikelet_type]['enabled']
          @logger.debug "coordinator is now initialising the #{pikelet_type} pikelet"
          pikelet_cfg = @config[pikelet_type]

          case pikelet_type
          when 'executive', 'jabber_gateway', 'pagerduty_gateway'
            build_pikelet(pikelet_type, pikelet_cfg)
          when 'web', 'api'
            build_thin_pikelet(pikelet_type, pikelet_cfg)
          when 'email_notifier', 'sms_notifier'
            build_resque_pikelet(pikelet_type, pikelet_cfg)
          end
        end

        setup_signals
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
      end
      return unless pikelet_class

      pikelet = nil
      f = Fiber.new {
        begin
          pikelet = pikelet_class.new
          @pikelets << pikelet
          pikelet.bootstrap(:redis => @redis_options, :config => pikelet_cfg)
          pikelet.main
        rescue Exception => e
          trace = e.backtrace.join("\n")
          @logger.fatal "#{e.message}\n#{trace}"
          @pikelets.delete_if {|p| p == pikelet } if pikelet
          @pikelet_fibers.delete(pikelet_type)
          stop
        end
      }
      @pikelet_fibers[pikelet_type] = f
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

      pikelet_class.class_variable_set('@@redis', build_redis_connection_pool)

      Thin::Logging.silent = true

      pikelet = Thin::Server.new('0.0.0.0', port, pikelet_class, :signals => false)
      @pikelets << pikelet
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

      if ::Resque.redis.nil?
        # set up connection pooling, stop resque errors
        ::Resque.redis = build_redis_connection_pool
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

      f = Fiber.new {
        flapjack_rsq = nil
        begin
          # TODO error if pikelet_cfg['queue'].nil?
          flapjack_rsq = EM::Resque::Worker.new(pikelet_cfg['queue'])
          # # Use these to debug the resque workers
          # flapjack_rsq.verbose = true
          #flapjack_rsq.very_verbose = true
          @pikelets << flapjack_rsq
          flapjack_rsq.work(0.1)
        rescue Exception => e
          trace = e.backtrace.join("\n")
          @pikelets.delete_if {|p| p == flapjack_rsq } if flapjack_rsq
          @logger.fatal "#{e.message}\n#{trace}"
          stop
        end
      }
      @pikelet_fibers[pikelet_type] = f
      f.resume
      @logger.debug "new fiber created for #{pikelet_type}"
    end

    def build_redis_connection_pool(options = {})
      EventMachine::Synchrony::ConnectionPool.new(:size => options[:size] || 5) do
        ::Redis.new(@redis_options.merge(:driver => (options[:driver] || 'synchrony')))
      end
    end

    def health_check(thin_pikelets)
      @pikelet_fibers.each_pair do |n,f|
        @logger.debug "#{n}: #{f.alive? ? 'alive' : 'dead'}"
      end

      thin_pikelets.each do |tp|
        s = tp.backend.size
        @logger.debug "thin on port #{tp.port} - #{s} connections"
      end
    end

    def shutdown
      @pikelets.each do |pik|
        case pik
        when Flapjack::Executive, Flapjack::Jabber, Flapjack::Pagerduty
          pik.stop
          Fiber.new {
            # this needs to use a separate Redis connection from the pikelet's
            # one, as that's in the middle of its blpop
            r = Redis.new(@redis_options.merge(:driver => 'synchrony'))
            pik.add_shutdown_event(:redis => r)
            r.quit
          }.resume
        when EM::Resque::Worker
          # resque is polling, so we don't need a shutdown object
          pik.shutdown
        when Thin::Server # web, api
          # drop from this side, as HTTP keepalive etc. means browsers
          # keep connections alive for ages, and we'd be hanging around
          # waiting for them to drop
          pik.stop!
        end
      end

      Fiber.new {
        thin_pikelets = @pikelets.select {|p| p.is_a?(Thin::Server) }

        loop do
          health_check(thin_pikelets)

          if @pikelet_fibers.values.any?(&:alive?) ||
            thin_pikelets.any?{|tp| !tp.backend.empty? }
            EM::Synchrony.sleep 0.25
          else
            EM.stop
            break
          end
        end
      }.resume
    end

  end

end
