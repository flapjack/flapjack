#!/usr/bin/env ruby

# This class encapsulates the config data and environmental setup used
# by the various Flapjack components.
#
# "In Australia and New Zealand, small pancakes (about 75 mm in diameter) known as pikelets
# are also eaten. They are traditionally served with jam and/or whipped cream, or solely
# with butter, at afternoon tea, but can also be served at morning tea."
#    from http://en.wikipedia.org/wiki/Pancake

require 'monitor'

require 'eventmachine'
require 'em-synchrony'

# the redis/synchrony gems need to be required in this particular order, see
# the redis-rb README for details
require 'hiredis'
require 'redis/connection/synchrony'
require 'redis'
require 'em-resque'
require 'em-resque/worker'
require 'thin'

require 'flapjack/executive'
require 'flapjack/gateways/api'
require 'flapjack/gateways/jabber'
require 'flapjack/gateways/oobetet'
require 'flapjack/gateways/pagerduty'
require 'flapjack/gateways/email'
require 'flapjack/gateways/sms_messagenet'
require 'flapjack/gateways/web'
require 'flapjack/logger'

module Flapjack

  module Pikelet

    class Base

      include MonitorMixin

# =======
#     def self.create(type, opts = {})
#       pikelet = nil
#       [Flapjack::Pikelet::Generic,
#        Flapjack::Pikelet::Resque,
#        Flapjack::Pikelet::Thin].each do |kl|
#         next unless kl::PIKELET_TYPES[type]
#         break if pikelet = kl.create(type, opts)
#       end
#       pikelet
#     end
# >>>>>>> f51cdf46c3c738df2dff1421f0ea356163da78f7

      attr_accessor :siblings
      attr_reader :pikelet, :error

      def initialize(pikelet_class, shutdown, options = {})
        @pikelet_class = pikelet_class
        @settings      = pikelet_class.pikelet_settings

        @config        = options[:config]
        @redis_config  = options[:redis_config]
        @logger        = options[:logger]
        @boot_time     = options[:boot_time]
        @shutdown      = shutdown

        @siblings      = []

        mon_initialize
      end

      def start(&block)
        @condition = new_cond

        @thread = Thread.new do
          Thread.current.abort_on_exception = true

          synchronize do
            EM.error_handler do |err|
              @logger.warn err.message
              trace = err.backtrace
              @logger.warn trace.join("\n") if trace
              @error = err
              EM.stop_event_loop if EM.reactor_running?
            end
            action = proc {
              begin
                yield
              rescue Exception => e
                @logger.warn e.message
                trace = e.backtrace
                @logger.warn trace.join("\n") if trace
                @error = e
              ensure
                EM.stop_event_loop if EM.reactor_running? && (@error || !!@settings[:em_stop])
              end
            }

            # TODO rename this, it's only relevant in the error case
            max_runs = @config['max_runs'] || 1
            runs = 0

            loop do
              @error = nil
              EM.send(!!@settings[:em_synchrony] ? :synchrony : :run, &action)
              runs += 1
              break unless @error && (max_runs > 0) && (runs < max_runs)
            end

            @finished = true

            if @error
              @shutdown.call
            else
              @condition.signal
            end
          end
        end
      end

      def reload(cfg, &block)
        @logger.configure(cfg['logger'])
        yield
      end

      def stop(&block)
        return if @thread.nil?
        yield
        synchronize do
          @condition.wait_until { @finished }
        end
        @thread.join
        @thread = nil
      end
    end

    class Generic < Flapjack::Pikelet::Base

      TYPES = ['executive', 'jabber', 'oobetet', 'pagerduty']
# =======
#      PIKELET_TYPES = {'executive'  => Flapjack::Executive,
#                       'jabber'     => Flapjack::Gateways::Jabber,
#                       'pagerduty'  => Flapjack::Gateways::Pagerduty,
#                       'oobetet'    => Flapjack::Gateways::Oobetet}

#       def self.create(type, opts = {})
#         self.new(type, PIKELET_TYPES[type], :config => opts[:config],
#           :redis_config => opts[:redis_config],
#           :boot_time => opts[:boot_time])
#       end

#       def initialize(type, pikelet_klass, opts = {})
#         super(type, pikelet_klass, opts)
#         @pikelet = @klass.new(opts.merge(:logger => @logger))
#       end
# >>>>>>> f51cdf46c3c738df2dff1421f0ea356163da78f7

      def start
        super do
          @pikelet = @pikelet_class.new(:config => @config,
            :redis_config => @redis_config, :logger => @logger,
            :siblings => siblings.map(&:pikelet))
          @pikelet.start
        end
      end

      # this should only reload if all changes can be applied -- will
      # return false to log warning otherwise
      def reload(cfg)
        return false unless @pikelet.respond_to?(:reload)
        super(cfg) { @pikelet.reload(cfg) }
      end

      def stop
        super { @pikelet.stop }
      end
    end

    class HTTP < Flapjack::Pikelet::Base
# =======
#     class Resque < Flapjack::Pikelet::Base

#       PIKELET_TYPES = {'email' => Flapjack::Gateways::Email,
#                        'sms'   => Flapjack::Gateways::SmsMessagenet}

#       def self.create(type, opts = {})
#         self.new(type, PIKELET_TYPES[type], :config => opts[:config],
#           :redis_config => opts[:redis_config],
#           :boot_time => opts[:boot_time])
#       end
# >>>>>>> f51cdf46c3c738df2dff1421f0ea356163da78f7

      TYPES = ['web', 'api']

      def start
        @pikelet_class.instance_variable_set('@config', @config)
        @pikelet_class.instance_variable_set('@redis_config', @redis_config)
        @pikelet_class.instance_variable_set('@logger', @logger)

        if @config
          port = @config['port']
          port = port.nil? ? nil : port.to_i
          timeout = @config['timeout']
          timeout = timeout.nil? ? 300 : timeout.to_i
        end
        port = 3001 if (port.nil? || port <= 0 || port > 65535)

        super do
          @server = ::Thin::Server.new('0.0.0.0', port,
                                       @pikelet_class, :signals => false)
          @server.timeout = timeout
          @pikelet_class.start if @pikelet_class.respond_to?(:start)
          @server.start
        end
      end

      # this should only reload if all changes can be applied -- will
      # return false to log warning otherwise
      def reload(cfg)
         # TODO fail if port changes
        return false unless @pikelet_class.respond_to?(:reload)
        super(cfg) { @pikelet_class.reload(cfg) }
      end

      def stop
        super do
          @server.stop!
          @pikelet_class.stop if @pikelet_class.respond_to?(:stop)
          @thread.run if @thread.alive?
        end
      end
    end

    class Resque < Flapjack::Pikelet::Base

      TYPES = ['email', 'sms']

      def start
        @pikelet_class.instance_variable_set('@config', @config)
        @pikelet_class.instance_variable_set('@redis_config', @redis_config)
        @pikelet_class.instance_variable_set('@logger', @logger)
      # def self.create(type, opts = {})
      #   ::Thin::Logging.silent = true
      #   self.new(type, PIKELET_TYPES[type], :config => opts[:config],
      #     :redis_config => opts[:redis_config],
      #     :boot_time => opts[:boot_time])
      # end

        super do
          @pikelet_class.start if @pikelet_class.respond_to?(:start)

          @worker = EM::Resque::Worker.new(@config['queue'])
          # # Use these to debug the resque workers
          # @worker.verbose = true
          # @worker.very_verbose = true

          # work only finishes when the pikelet does
          @worker.work(0.1)
        end
      end

      # this should only reload if all changes can be applied -- will
      # return false to log warning otherwise
      def reload(cfg)
        return false unless @pikelet_class.respond_to?(:reload)
        super(cfg) { @pikelet_class.reload(cfg) }
      end

      def stop
        super do
          @worker.shutdown if @worker
          @pikelet_class.stop if @pikelet_class.respond_to?(:stop)
        end
      end
    end

    WRAPPERS = [Flapjack::Pikelet::Generic, Flapjack::Pikelet::Resque,
                Flapjack::Pikelet::HTTP]

    TYPES = {'api'        => [Flapjack::Gateways::API],
             'email'      => [Flapjack::Gateways::Email],
             'executive'  => [Flapjack::Executive],
             'jabber'     => [Flapjack::Gateways::Jabber::Bot,
                              Flapjack::Gateways::Jabber::Notifier],
             'oobetet'    => [Flapjack::Gateways::Oobetet::Bot,
                              Flapjack::Gateways::Oobetet::Notifier],
             'pagerduty'  => [Flapjack::Gateways::Pagerduty],
             'sms'        => [Flapjack::Gateways::SmsMessagenet],
             'web'        => [Flapjack::Gateways::Web],
            }

    def self.is_pikelet?(type)
      TYPES.has_key?(type)
    end

    def self.create(type, shutdown, opts = {})
      config = opts[:config] || {}
      redis_config = opts[:redis_config] || {}

      logger = Flapjack::Logger.new("flapjack-#{type}", config['logger'])

      types = TYPES[type]

      return [] if types.nil?

      created = types.collect {|pikelet_class|
        wrapper = WRAPPERS.detect {|wrap| wrap::TYPES.include?(type) }
        wrapper.new(pikelet_class, shutdown, :config => config,
                    :redis_config => redis_config, :logger => logger)
      }
      created.each {|c| c.siblings = created - [c] }
      created
    end

  end

end
