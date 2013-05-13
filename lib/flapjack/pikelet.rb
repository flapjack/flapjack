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
      attr_reader :type, :status

      def initialize(type, pikelet_class, opts = {})
        @type = type
        @klass = pikelet_class

        @config = opts[:config] || {}
        @redis_config = opts[:redis_config] || {}

        @logger = Flapjack::Logger.new("flapjack-#{type}", @config['logger'])

        @status = 'initialized'
      end

      def block_until_finished
        return if @thread.nil?
        @thread.join
        @thread = nil
      end

      def start
        @status = 'started'
      end

      def reload(cfg)
        @logger.configure(cfg['logger'])
        true
      end

      def stop
        @status = 'stopping'
      end
    end

    class Generic < Flapjack::Pikelet::Base

     PIKELET_TYPES = {'executive'  => Flapjack::Executive,
                      'pagerduty'  => Flapjack::Gateways::Pagerduty}

      def initialize(type, pikelet_klass, opts = {})
        super(type, pikelet_klass, opts)
        @pikelet = @klass.new(opts.merge(:logger => @logger))
      end

      def start
        @thread = Thread.new {
          EM.sync {
            begin
              @pikelet.start
            rescue Exception => e
              @logger.warn e.message
              @logger.warn e.backtrace.join("\n")
            end
          }
        }
        super
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

      def update_status
        return @status unless 'stopping'.eql?(@status)
        @status = 'stopped' if @fiber && !@fiber.alive?
      end
    end

    class Resque < Flapjack::Pikelet::Base

      PIKELET_TYPES = {'email' => Flapjack::Gateways::Email,
                       'sms'   => Flapjack::Gateways::SmsMessagenet}

      def self.sync_safe?
        true
      end

      def initialize(type, pikelet_klass, opts = {})
        super(type, pikelet_klass, opts)

        pikelet_klass.instance_variable_set('@config', @config)
        pikelet_klass.instance_variable_set('@redis_config', @redis_config)
        pikelet_klass.instance_variable_set('@logger', @logger)

        unless defined?(@@resque_pool) && !@@resque_pool.nil?
          @@resque_pool = Flapjack::RedisPool.new(:config => @redis_config)
          ::Resque.redis = @@resque_pool
        end

        # TODO error if config['queue'].nil?

        @worker = EM::Resque::Worker.new(@config['queue'])
        # # Use these to debug the resque workers
        # worker.verbose = true
        # worker.very_verbose = true
      end

      def start
        @thread = Thread.new {
          @klass.start if @klass.respond_to?(:start)
          EM.sync {
            begin
              @worker.work(0.1)
            rescue Exception => e
              @logger.warn e.message
              @logger.warn e.backtrace.join("\n")
            end
          }
        }
        super
      end

      # this should only reload if all changes can be applied -- will
      # return false to log warning otherwise
      def reload(cfg)
        @klass.respond_to?(:reload) ?
          (@klass.reload(cfg) && super(cfg)) : super(cfg)
      end

      def stop
        @worker.shutdown if @worker && @fiber && @fiber.alive?
        @klass.stop if @klass.respond_to?(:stop)
        super
      end

      def update_status
        return @status unless 'stopping'.eql?(@status)
        @status = 'stopped' if @fiber && !@fiber.alive?
      end
    end

    class Blather < Flapjack::Pikelet::Base

     PIKELET_TYPES = {'jabber'     => Flapjack::Gateways::Jabber,
                      'oobetet'    => Flapjack::Gateways::Oobetet}

      def self.sync_safe?
        false
      end

      def initialize(type, pikelet_klass, opts = {})
        super(type, pikelet_klass, opts)
        @pikelet = @klass.new(opts.merge(:logger => @logger))
      end

      def start
        @thread = Thread.new {
          EM.run {
            begin
              @pikelet.start
            rescue Exception => e
              @logger.warn e.message
              @logger.warn e.backtrace.join("\n")
            end
          }
        }
        super
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

      def update_status
        return @status unless 'stopping'.eql?(@status)
        @status = 'stopped' if @fiber && !@fiber.alive?
      end

    end

    class Thin < Flapjack::Pikelet::Base

      PIKELET_TYPES = {'web'  => Flapjack::Gateways::Web,
                       'api'  => Flapjack::Gateways::API}

      def self.sync_safe?
        false
      end

      def initialize(type, pikelet_klass, opts = {})
        super(type, pikelet_klass, opts)

        pikelet_klass.instance_variable_set('@config', @config)
        pikelet_klass.instance_variable_set('@redis_config', @redis_config)
        pikelet_klass.instance_variable_set('@logger', @logger)

        if @config
          @port = @config['port']
          @port = @port.nil? ? nil : @port.to_i
        end
        @port = 3001 if (@port.nil? || @port <= 0 || @port > 65535)

        @server = ::Thin::Server.new('0.0.0.0', @port,
                    @klass, :signals => false)
      end

      def start

        @thread = Thread.new {
          EM.run {
            begin
            @klass.start if @klass.respond_to?(:start)
            @server.start
            rescue Exception => e
              @logger.warn e.message
              @logger.warn e.backtrace.join("\n")
            end
          }
        }
        super
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

      def update_status
        return @status unless 'stopping'.eql?(@status)
        @status = 'stopped' if (@server.backend.size <= 0)
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
