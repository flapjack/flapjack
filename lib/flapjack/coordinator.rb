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

require 'flapjack/api'
require 'flapjack/daemonizing'
require 'flapjack/notification/email'
require 'flapjack/notification/sms'
require 'flapjack/notification/jabber'
require 'flapjack/executive'
require 'flapjack/web'

module Flapjack

  class Coordinator

    include Flapjack::Daemonizable

    def initialize(config = {})
      @config = config
      @pikelets = []
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

    # clean shutdown
    def stop
      @pikelets.each do |pik|
        case pik
        when Flapjack::Executive
          pik.stop
          Fiber.new {
            pik.add_shutdown_event
          }.resume
        when EM::Resque::Worker
          # resque is polling, so we don't need a shutdown object
          pik.shutdown
        when Thin::Server # web, api
          pik.stop
        end
      end
      # FIXME only call EM.stop after polling to check whether all of the
      # above have finished
      EM.stop
    end

    # not-so-clean shutdown
    def stop!
      stop
      # FIXME wrap the above in a timeout?
    end

  private

    def setup

      # TODO if we want to run the same pikelet with different settings,
      # we could require each setting to include a type, and treat the
      # key as the name of the config -- for now, YAGNI.

      # TODO store these in the classes themselves, register pikelets here?
      pikelet_types = {
        'executive'       => Flapjack::Executive,
        'web'             => Flapjack::Web,
        'api'             => Flapjack::API,
        'email_notifier'  => Flapjack::Notification::Email,
        'sms_notifier'    => Flapjack::Notification::Sms,
        'jabber_notifier' => Flapjack::Notification::Jabber
      }

      EM.synchrony do

        redis_sync = ::Redis.new(@config['redis'].merge(:driver => 'synchrony'))
        redis_ruby = ::Redis.new(@config['redis'].merge(:driver => 'ruby'))

        unless (['email_notifier', 'sms_notifier'] & @config.keys).empty?
          # make Resque a slightly nicer citizen
          require 'flapjack/resque_patches'
          # set up connection pooling, stop resque errors
          EM::Resque.initialize_redis(::Redis.new(@config['redis']))
        end

        @config.keys.each do |pikelet_type|
          next unless pikelet_types.has_key?(pikelet_type)
          pikelet_cfg = @config[pikelet_type]

          case pikelet_type
          when 'executive'
            Fiber.new {
              flapjack_exec = Flapjack::Executive.new(pikelet_cfg.merge(:redis => redis_sync))
              @pikelets << flapjack_exec
              flapjack_exec.main
            }.resume
          when 'email_notifier', 'sms_notifier'

            # See https://github.com/mikel/mail/blob/master/lib/mail/mail.rb#L53
            # & https://github.com/mikel/mail/blob/master/spec/mail/configuration_spec.rb
            # for details of configuring mail gem. defaults to SMTP, localhost, port 25
            Mail.defaults { delivery_method :smtp, {:enable_starttls_auto => false} }

            # TODO error if pikelet_cfg['queue'].nil?

            # # Deferring this: Resque's not playing well with evented code
            # if 'email_notifier'.eql?(pikelet_type)
            #   pikelet = pikelet_types[pikelet_type]
            #   pikelet.class_variable_set('@@actionmailer_config', actionmailer_config)
            # end

            Fiber.new {
              flapjack_rsq = EM::Resque::Worker.new(pikelet_cfg['queue'])
              # # Use these to debug the resque workers
              # flapjack_rsq.verbose = true
              # flapjack_rsq.very_verbose = true
              @pikelets << flapjack_rsq
              flapjack_rsq.work(0.1)
            }.resume
          when 'jabber_gateway'
            Fiber.new {
              flapjack_jabbers = Flapjack::Notification::Jabber.new(:redis => redis_sync,
                :config => pikelet_cfg)
              flapjack_jabbers.main
            }.resume
          when 'web'
            port = nil
            if pikelet_cfg['port']
              port = pikelet_cfg['port'].to_i
            end

            port = 3000 if port.nil? || port <= 0 || port > 65535

            Flapjack::Web.class_variable_set('@@redis', redis_ruby)

            Thin::Logging.silent = true

            web = Thin::Server.new('0.0.0.0', port, Flapjack::Web, :signals => false)
            @pikelets << web
            web.start
          when 'api'
            port = nil
            if pikelet_cfg['port']
              port = pikelet_cfg['port'].to_i
            end

            port = 3001 if port.nil? || port <= 0 || port > 65535

            Flapjack::API.class_variable_set('@@redis', redis_ruby)

            Thin::Logging.silent = true

            api = Thin::Server.new('0.0.0.0', port, Flapjack::API, :signals => false)
            @pikelets << api
            api.start
          end

        end

        setup_signals
      end

    end

    def setup_signals
      trap('INT')  { stop! }
      trap('TERM') { stop }
      unless RUBY_PLATFORM =~ /mswin/
        trap('QUIT') { stop }
        # trap('HUP')  { restart }
        # trap('USR1') { reopen_log }
      end
    end

  end

end
