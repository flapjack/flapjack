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

      # TODO if we want to run the same pikelet with different settings,
      # we could require each setting to include a type, and treat the
      # key as the name of the config -- for now, YAGNI.

      # TODO store these in the classes themselves, register pikelets here?
      pikelet_types = {
        'executive'       => Flapjack::Executive,
        'api'             => Flapjack::API,
        'jabber_gateway'  => Flapjack::Jabber,
        'web'             => Flapjack::Web,
        'email_notifier'  => Flapjack::Notification::Email,
        'sms_notifier'    => Flapjack::Notification::Sms
      }

      # FIXME: the following is currently repeated in flapjack-populator and
      # flapjack-nagios-receiver - move to a method in a module and include it
      redis_host = @config['redis']['host'] || '127.0.0.1'
      redis_port = @config['redis']['port'] || 6379
      redis_path = @config['redis']['path'] || nil
      redis_db   = @config['redis']['db']   || 0

      if redis_path
        redis_options = { :db => redis_db, :path => redis_path }
      else
        redis_options = { :db => redis_db, :host => redis_host, :port => redis_port }
      end

      EM.synchrony do

        @logger.debug "config keys: #{@config.keys}"
        unless (['email_notifier', 'sms_notifier'] & @config.keys).empty?
          # set up connection pooling, stop resque errors
          ::Resque.redis = EventMachine::Synchrony::ConnectionPool.new(:size => 5) do
            ::Redis.new(redis_options.merge(:driver => :synchrony))
          end
          # # NB: can override the default 'resque' namespace like this
          # ::Resque.redis.namespace = 'flapjack'
        end

        unless (['web', 'api'] & @config.keys).empty?
          Thin::Logging.silent = true
        end

        @config.keys.each do |pikelet_type|
          next unless pikelet_types.has_key?(pikelet_type)
          next unless @config[pikelet_type]['enabled']
          @logger.debug "coordinator is now initialising the #{pikelet_type} pikelet(s)"
          pikelet_cfg = @config[pikelet_type]
          case pikelet_type
          when 'executive'
            f = Fiber.new {
              flapjack_exec = Flapjack::Executive.new(
                pikelet_cfg.merge(
                  :redis => ::Redis.new(redis_options.merge(:driver => 'synchrony')),
                  :redis_config => redis_options
                )
              )
              @pikelets << flapjack_exec
              flapjack_exec.main
            }
            @pikelet_fibers[pikelet_type] = f
            f.resume
            @logger.debug "new fiber created for #{pikelet_type}"
          when 'email_notifier', 'sms_notifier'

            pikelet = pikelet_types[pikelet_type]

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

            pikelet.class_variable_set('@@config', pikelet_cfg)

            f = Fiber.new {
              # TODO error if pikelet_cfg['queue'].nil?
              flapjack_rsq = EM::Resque::Worker.new(pikelet_cfg['queue'])
              # # Use these to debug the resque workers
              # flapjack_rsq.verbose = true
              #flapjack_rsq.very_verbose = true
              @pikelets << flapjack_rsq
              flapjack_rsq.work(0.1)
            }
            @pikelet_fibers[pikelet_type] = f
            f.resume
            @logger.debug "new fiber created for #{pikelet_type}"
          when 'jabber_gateway'
            f = Fiber.new {
              flapjack_jabber = Flapjack::Jabber.new(:redis =>
                ::Redis.new(redis_options.merge(:driver => 'synchrony')),
                :redis_config => redis_options,
                :config => pikelet_cfg)
              @pikelets << flapjack_jabber
              flapjack_jabber.setup
              flapjack_jabber.main
            }
            @pikelet_fibers[pikelet_type] = f
            f.resume
            @logger.debug "new fiber created for #{pikelet_type}"
          when 'web'
            port = nil
            if pikelet_cfg['port']
              port = pikelet_cfg['port'].to_i
            end

            port = 3000 if (port.nil? || port <= 0 || port > 65535)

            Flapjack::Web.class_variable_set('@@redis',
              ::Redis.new(redis_options.merge(:driver => 'ruby')))

            web = Thin::Server.new('0.0.0.0', port, Flapjack::Web, :signals => false)
            @pikelets << web
            web.start
            @logger.debug "new thin server instance started for #{pikelet_type}"
          when 'api'
            port = nil
            if pikelet_cfg['port']
              port = pikelet_cfg['port'].to_i
            end

            port = 3001 if (port.nil? || port <= 0 || port > 65535)

            Flapjack::API.class_variable_set('@@redis',
              ::Redis.new(redis_options.merge(:driver => 'ruby')))

            api = Thin::Server.new('0.0.0.0', port, Flapjack::API, :signals => false)
            @pikelets << api
            api.start
            @logger.debug "new thin server instance started for #{pikelet_type}"
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

    # def health_check(thin_pikelets)
    #   @pikelet_fibers.each_pair do |n,f|
    #     @logger.debug "#{n}: #{f.alive? ? 'alive' : 'dead'}"
    #   end
    #
    #   thin_pikelets.each do |tp|
    #     s = tp.backend.size
    #     @logger.debug "thin on port #{tp.port} - #{s} connections"
    #   end
    # end

    def shutdown
      @pikelets.each do |pik|
        case pik
        when Flapjack::Executive, Flapjack::Jabber
          pik.stop
          Fiber.new {
            pik.add_shutdown_event
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
          # health_check(thin_pikelets)

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
