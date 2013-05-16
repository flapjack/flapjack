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
      attr_reader :type

      def initialize(type, pikelet_class, opts = {})
        @type = type
        @klass = pikelet_class

        @config = opts[:config] || {}
        @redis_config = opts[:redis_config] || {}

        # TODO is logger threadsafe?
        @logger = Flapjack::Logger.new("flapjack-#{type}", @config['logger'])

        @monitor = Monitor.new
      end

      def start(&block)
        @thread = Thread.new do
          Thread.current.abort_on_exception = true

          @monitor.synchronize do
            EM.run do
              EM.error_handler do |err|
                @logger.warn err.message
                trace = err.backtrace
                @logger.warn trace.join("\n") if trace
                @error = err
                EM.stop_event_loop
              end
              yield
            end
          end

          # TODO propagate higher-level shutdown instead -- or restart
          # pikelet -- might depend on the exception type?
          Kernel.raise @error if @error
        end
      end

      def reload(cfg)
        @logger.configure(cfg['logger'])
        true
      end

      def stop
        @logger.info "check for stop, wait if required"
        @monitor.synchronize do
          if @error
            @logger.info "had error #{e.message}"
          end
          @logger.info "has stopped"
        end
      end

    end

    class Generic < Flapjack::Pikelet::Base

      PIKELET_TYPES = {'executive'  => Flapjack::Executive,
                       'pagerduty'  => Flapjack::Gateways::Pagerduty}

      def start
        super do
          EM.synchrony do
            begin
              @pikelet = @klass.new(:config => @config,
                :redis_config => @redis_config, :logger => @logger)
              # start only finishes when the pikelet does
              @pikelet.start
            rescue Exception => e
              @logger.warn e.message
              trace = e.backtrace
              @logger.warn trace.join("\n") if trace
              @error = e
            end
            EM.stop_event_loop
          end
        end
      end

      # this should only reload if all changes can be applied -- will
      # return false to log warning otherwise
      def reload(cfg)
        # TODO what if start didn't work?
        @pikelet.respond_to?(:reload) ?
          (@pikelet.reload(cfg) && super(cfg)) : super(cfg)
      end

      def stop
        # TODO what if start didn't work?
        @pikelet.stop
        super
      end
    end

    class Resque < Flapjack::Pikelet::Base

      PIKELET_TYPES = {'email' => Flapjack::Gateways::Email,
                       'sms'   => Flapjack::Gateways::SmsMessagenet}

      def initialize(type, pikelet_klass, opts = {})
        super(type, pikelet_klass, opts)

        pikelet_klass.instance_variable_set('@config', @config)
        pikelet_klass.instance_variable_set('@redis_config', @redis_config)
        pikelet_klass.instance_variable_set('@logger', @logger)
      end

      def start
        super do
          EM.synchrony do
            begin
              @klass.start if @klass.respond_to?(:start)

              unless defined?(@@resque_pool) && !@@resque_pool.nil?
                @@resque_pool = Flapjack::RedisPool.new(:config => @redis_config)
                ::Resque.redis = @@resque_pool
              end

              # TODO error if config['queue'].nil?

              @worker = EM::Resque::Worker.new(@config['queue'])
              # # Use these to debug the resque workers
              # worker.verbose = true
              # worker.very_verbose = true

              # work only finishes when the pikelet does
              @worker.work(0.1)
            rescue Exception => e
              @logger.warn e.message
              trace = e.backtrace
              @logger.warn trace.join("\n") if trace
              @error = e
            end
            EM.stop_event_loop
          end
        end
      end

      # this should only reload if all changes can be applied -- will
      # return false to log warning otherwise
      def reload(cfg)
        # TODO what if start didn't work?
        @pikelet.respond_to?(:reload) ?
          (@pikelet.reload(cfg) && super(cfg)) : super(cfg)
      end

      def stop
        # TODO what if start didn't work?
        @worker.shutdown if @worker && @fiber && @fiber.alive?
        @klass.stop if @klass.respond_to?(:stop)
        super
      end
    end

    class Blather < Flapjack::Pikelet::Base

      PIKELET_TYPES = {'jabber'     => Flapjack::Gateways::Jabber,
                       'oobetet'    => Flapjack::Gateways::Oobetet}

      def start
        super do
          begin
            @pikelet = @klass.new(:config => @config,
              :redis_config => @redis_config, :logger => @logger)
            @pikelet.start
          rescue Exception => e
            @logger.warn e.message
            trace = e.backtrace
            @logger.warn trace.join("\n") if trace
            @error = e
          end

          EM.stop_event_loop
        end
      end

      # this should only reload if all changes can be applied -- will
      # return false to log warning otherwise
      def reload(cfg)
        @pikelet.respond_to?(:reload) ?
          (@pikelet.reload(cfg) && super(cfg)) : super(cfg)
      end

      def stop
        @pikelet.stop
        super
      end
    end

    class Thin < Flapjack::Pikelet::Base

      PIKELET_TYPES = {'web'  => Flapjack::Gateways::Web,
                       'api'  => Flapjack::Gateways::API}

      def initialize(type, pikelet_klass, opts = {})
        super(type, pikelet_klass, opts)

        pikelet_klass.instance_variable_set('@config', @config)
        pikelet_klass.instance_variable_set('@redis_config', @redis_config)
        pikelet_klass.instance_variable_set('@logger', @logger)
      end

      def start
        super do
          begin
            if @config
              @port = @config['port']
              @port = @port.nil? ? nil : @port.to_i
              @timeout = @config['timeout']
              @timeout = @timeout.nil? ? 300 : @timeout.to_i
            end
            @port = 3001 if (@port.nil? || @port <= 0 || @port > 65535)

            @server = ::Thin::Server.new('0.0.0.0', @port,
                        @klass, :signals => false)
            @server.timeout = @timeout

            @klass.start if @klass.respond_to?(:start)
            @server.start
          rescue Exception => e
            @logger.warn e.message
            trace = e.backtrace
            @logger.warn trace.join("\n") if trace
            @error = e
          end
          # NB: Thin itself calls EM.stop within server.stop!
        end
      end

      # this should only reload if all changes can be applied -- will
      # return false to log warning otherwise
      def reload(cfg)
        # TODO fail if port changes
        @klass.respond_to?(:reload) ?
          (@klass.reload(cfg) && super(cfg)) : super(cfg)
      end

      def stop
        @server.stop!
        @klass.stop if @klass.respond_to?(:stop)
        super
      end
    end

    # TODO find a better way of expressing this
    WRAPPERS = [Flapjack::Pikelet::Generic, Flapjack::Pikelet::Resque,
                Flapjack::Pikelet::Blather, Flapjack::Pikelet::Thin]

    TYPES    = WRAPPERS.inject({}) do |memo, type|
                 memo.update(type::PIKELET_TYPES)
               end

    def self.is_pikelet?(type)
      TYPES.has_key?(type)
    end

    def self.wrapper_for_type(type)
      WRAPPERS.detect {|kl| kl::PIKELET_TYPES.keys.include?(type) }
    end

    def self.create(type, opts = {})
      return unless wrapper = wrapper_for_type(type)
      wrapper.new(type, TYPES[type], opts)
    end
  end

end
