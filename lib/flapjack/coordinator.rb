#!/usr/bin/env ruby

require 'em-resque/worker'

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
        setup_signals
      end
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
          # resque is polling, so won't need a shutdown object
          pik.shutdown
        when Thin::Server
          pik.stop
        end
      end
      # # TODO call EM.stop after polling to check whether all of the
      # # above have finished
      # EM.stop
    end

    # not-so-clean shutdown
    def stop!
      stop
      # FIXME wrap the above in a timeout?
    end

    def after_daemonize
      # FIXME ideally we'd setup_signals after setup, but something in web is blocking
      # when we're running daemonized :/
      setup_signals
      setup
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

  private

    def setup

      # TODO if we want to run the same pikelet with different settings,
      # we could require each setting to include a type, and treat the
      # key as the name of the config -- for now, YAGNI.

      # TODO store these in the classes themselves, register pikelets here?
      pikelet_types = {
        'executive'      => Flapjack::Executive,
        'web'            => Flapjack::Web,
        'email_notifier' => Flapjack::Notification::Email,
        'sms_notifier'   => Flapjack::Notification::Sms
      }

      EM.synchrony do
        unless (['email_notifier', 'sms_notifier'] & @config.keys).empty?
          # make Resque a slightly nicer citizen
          require 'flapjack/resque_patches'
          # set up connection pooling, stop resque errors
          EM::Resque.initialize_redis(::Redis.new(@config['redis']))
        end

        def fiberise_instances(instance_num, &block)
          (1..[1, instance_num || 1].max).each do |n|
            Fiber.new {
              block.yield
            }.resume
          end
        end

        @config.keys.each do |pikelet_type|
          next unless pikelet_types.has_key?(pikelet_type)
          pikelet_cfg = @config[pikelet_type]

          case pikelet_type
          when 'executive'
            fiberise_instances(pikelet_cfg['instances'].to_i) {
              flapjack_exec = Flapjack::Executive.new(pikelet_cfg.merge(:redis => {:driver => 'synchrony'}))
              @pikelets << flapjack_exec
              flapjack_exec.main
            }
          when 'email_notifier', 'sms_notifier'
            pikelet = pikelet_types[pikelet_type]

            # TODO error if pikelet_cfg['queue'].nil?

            # # Deferring this: Resque's not playing well with evented code
            # if 'email_notifier'.eql?(pikelet_type)
            #   pikelet.class_variable_set('@@actionmailer_config', actionmailer_config)
            # end

            fiberise_instances(pikelet_cfg['instances']) {
              flapjack_rsq = EM::Resque::Worker.new(pikelet_cfg['queue'])
              # # Use these to debug the resque workers
              # flapjack_rsq.verbose = true
              # flapjack_rsq.very_verbose = true
              @pikelets << flapjack_rsq
              flapjack_rsq.work(0.1)
            }
          when 'jabber_gateway'
            fiberise_instances(pikelet_cfg['instances']) {
              flapjack_jabbers = Flapjack::Notification::Jabber.new(pikelet_cfg)
              flapjack_jabbers.main
            }
          when 'web'
            port = nil
            if pikelet_cfg['thin_config'] && pikelet_cfg['thin_config']['port']
              port = pikelet_cfg['thin_config']['port'].to_i
            end

            port = 3000 if port.nil? || port <= 0 || port > 65535

            thin = Thin::Server.new('0.0.0.0', port, Flapjack::Web, :signals => false)
            @pikelets << thin
            thin.start
          end

        end

      end

    end

  end

end
