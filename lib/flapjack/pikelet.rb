#!/usr/bin/env ruby

# This class encapsulates the config data and environmental setup used
# by the various Flapjack components.
#
# "In Australia and New Zealand, small pancakes (about 75 mm in diameter) known as pikelets
# are also eaten. They are traditionally served with jam and/or whipped cream, or solely
# with butter, at afternoon tea, but can also be served at morning tea."
#    from http://en.wikipedia.org/wiki/Pancake

require 'eventmachine'
require 'em-synchrony'

# the redis/synchrony gems need to be required in this particular order, see
# the redis-rb README for details
require 'hiredis'
require 'redis/connection/synchrony'
require 'redis'
require 'em-resque'
require 'em-resque/worker'

require 'monitor'

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
require 'thin/version'

module Flapjack

  module Pikelet

    class Base

      include MonitorMixin

      def initialize(pikelet_class, options = {})
        @pikelet_class = pikelet_class
        @settings      = pikelet_class.respond_to?(:pikelet_settings) ?
                           pikelet_class.pikelet_settings : {}

        @config        = options[:config]
        @redis_config  = options[:redis_config]
        @logger        = options[:logger]

        mon_initialize
      end

      def start(&block)
        @condition     = new_cond

        @thread = Thread.new do
          Thread.current.abort_on_exception = true

          synchronize do
            action = proc {
              EM.error_handler do |err|
                @logger.warn err.message
                trace = err.backtrace
                @logger.warn trace.join("\n") if trace
                @error = err
                EM.stop_event_loop
              end
              begin
                yield
              rescue Exception => e
                @logger.warn e.message
                trace = e.backtrace
                @logger.warn trace.join("\n") if trace
                @error = e
              end
              EM.stop_event_loop if !!@settings[:em_stop]
            }

            EM.send(!!@settings[:em_synchrony] ? :synchrony : :run, &action)
            @finished = true
            @condition.signal
          end
          # TODO propagate higher-level shutdown instead -- or restart
          # pikelet -- might depend on the exception type?
          Kernel.raise @error if @error
        end
      end

      # def reload(cfg)
      # end

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

      def start
        super do
          @pikelet = @pikelet_class.new(:config => @config,
            :redis_config => @redis_config, :logger => @logger)
          @pikelet.start
        end
      end

      # # this should only reload if all changes can be applied -- will
      # # return false to log warning otherwise
      # def reload(cfg)
      #   super(cfg) do
      #     # TODO what if start didn't work?
      #     @pikelet.respond_to?(:reload) ?
      #       (@pikelet.reload(cfg) && super(cfg)) : super(cfg)
      #   end
      # end

      def stop
        super { @pikelet.stop }
      end
    end

    class HTTP < Flapjack::Pikelet::Base

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

      # # this should only reload if all changes can be applied -- will
      # # return false to log warning otherwise
      # def reload(cfg)
      #   super do
      #     # TODO fail if port changes
      #     @pikelet_class.respond_to?(:reload) ?
      #       (@pikelet_class.reload(cfg) && super(cfg)) : super(cfg)
      #   end
      # end

      def stop
        super do
          @server.stop!
          @pikelet_class.stop if @pikelet_class.respond_to?(:stop)
        end
      end
    end

    class Resque < Flapjack::Pikelet::Base

      TYPES = ['email', 'sms']

      def start
        @pikelet_class.instance_variable_set('@config', @config)
        @pikelet_class.instance_variable_set('@redis_config', @redis_config)
        @pikelet_class.instance_variable_set('@logger', @logger)

        super do
          @pikelet_class.start if @pikelet_class.respond_to?(:start)

          # TODO move to class
          unless defined?(@@resque_pool) && !@@resque_pool.nil?
            @@resque_pool = Flapjack::RedisPool.new(:config => @redis_config)
            ::Resque.redis = @@resque_pool
          end

          @worker = EM::Resque::Worker.new(@config['queue'])
          # # Use these to debug the resque workers
          # @worker.verbose = true
          # @worker.very_verbose = true

          # work only finishes when the pikelet does
          @worker.work(0.1)
        end
      end

      # # this should only reload if all changes can be applied -- will
      # # return false to log warning otherwise
      # def reload(cfg)
      #   super do
      #     # TODO fail if port changes
      #     @pikelet_class.respond_to?(:reload) ?
      #       (@pikelet_class.reload(cfg) && super(cfg)) : super(cfg)
      #   end
      # end

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
             'oobetet'    => [Flapjack::Gateways::Oobetet],
             'pagerduty'  => [Flapjack::Gateways::Pagerduty],
             'sms'        => [Flapjack::Gateways::SmsMessagenet],
             'web'        => [Flapjack::Gateways::Web],
            }

    def self.is_pikelet?(type)
      TYPES.has_key?(type)
    end

    def self.create(type, opts = {})
      config = opts[:config] || {}
      redis_config = opts[:redis_config] || {}

      logger = Flapjack::Logger.new("flapjack-#{type}", config['logger'])

      types = TYPES[type]

      return [] if types.nil?

      types.collect {|pikelet_class|
        wrapper = WRAPPERS.detect {|wrap| wrap::TYPES.include?(type) }
        wrapper.new(pikelet_class, :config => config,
                    :redis_config => redis_config, :logger => logger)
      }
    end

  end

end
