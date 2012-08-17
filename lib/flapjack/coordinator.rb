#!/usr/bin/env ruby

require 'em-resque/worker'

require 'flapjack/daemonizing'
require 'flapjack/notification/email'
require 'flapjack/notification/sms'
require 'flapjack/executive'
require 'flapjack/web'

module Flapjack
  
  class Coordinator
    
    EVENTED_RESQUE = true # workers need to know what type of Redis connection to make
    
    include Flapjack::Daemonizable
    
    def initialize(config = {})
      @config = config
    end
    
    def start(options = {})
      # FIXME raise error if config not set, or empty
      
      if options[:daemonize]
        daemonize
        setup_signals
      else
        setup
        setup_signals
      end      
    end

    # needs to be visible to Daemonizable -- maybe try protected?
    def after_daemonize
      setup
    end
    
  private

    # FIXME handle these
    def setup_signals
      # trap('INT')  { stop! }
      # trap('TERM') { stop }
      unless RUBY_PLATFORM =~ /mswin/
        # trap('QUIT') { stop }
        # trap('HUP')  { restart }
        # trap('USR1') { reopen_log }
      end
    end

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
      
        def fiberise_instances(instance_num, &block)
          (1..[1, instance_num || 1].max).each do |n|
            Fiber.new {
              block.yield
            }.resume
          end
        end

        @config.keys.each do |pikelet_type|
          unless pikelet_types.has_key?(pikelet_type)
            # FIXME warning
            next
          end
          
          pikelet_cfg = @config[pikelet_type]
          
          case pikelet_type
          when 'executive'
            fiberise_instances(pikelet_cfg['instances'].to_i) {
              flapjack_exec = Flapjack::Executive.new(pikelet_cfg.merge(:evented => true))
              flapjack_exec.main     
            }
          when 'email_notifier', 'sms_notifier'
            pikelet = pikelet_types[pikelet_type]

            # # Deferring this pending discussion about execution model, Resque's not
            # # playing well with evented code
            # if 'email_notifier'.eql?(pikelet_type)
            #   pikelet.class_variable_set('@@actionmailer_config', actionmailer_config)
            # end

            fiberise_instances(pikelet_cfg['instances']) {
              flapjack_rsq = EM::Resque::Worker.new(pikelet.instance_variable_get('@queue'))
              # # Use these to debug the resque workers
              # flapjack_rsq.verbose = true
              # flapjack_rsq.very_verbose = true
              flapjack_rsq.work(0.1)
            }
          when 'web'
            # FIXME error if no thin config
            thin_opts = pikelet_cfg['thin_config'].to_a.collect {|a|
              ["--#{a[0]}", a[1].to_s]
            }.flatten  << 'start'
            ::Thin::Runner.new(thin_opts).run!
          end
          
        end

      end
  
    end

  end
  
end