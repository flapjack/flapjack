#!/usr/bin/env ruby

# This class encapsulates the config data and environmental setup used
# by the various Flapjack components.
#
# "In Australia and New Zealand, small pancakes (about 75 mm in diameter) known as pikelets
# are also eaten. They are traditionally served with jam and/or whipped cream, or solely
# with butter, at afternoon tea, but can also be served at morning tea."
#    from http://en.wikipedia.org/wiki/Pancake

require 'monitor'

require 'hiredis'
require 'redis'

require 'webrick'

require 'flapjack/notifier'
require 'flapjack/processor'
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

      attr_accessor :siblings
      attr_reader :pikelet, :error

      def initialize(pikelet_class, shutdown, options = {})
        @pikelet_class = pikelet_class

        @config        = options[:config]
        @redis_config  = options[:redis_config]
        @logger        = options[:logger]
        @boot_time     = options[:boot_time]
        @shutdown      = shutdown

        @siblings      = []

        mon_initialize

        @pikelet = @pikelet_class.new(:config => @config,
          :redis_config => @redis_config, :logger => @logger)
      end

      def start(&block)
        @pikelet.siblings = @siblings.map(&:pikelet) if @pikelet.respond_to?(:siblings=)

        @condition = new_cond

        @thread = Thread.new do
          Thread.current.abort_on_exception = true

          synchronize do
            # TODO rename this, it's only relevant in the error case
            max_runs = @config['max_runs'] || 1
            runs = 0

            error = nil

            loop do
              begin
                yield
              rescue Exception => e
                @logger.warn e.message
                trace = e.backtrace
                @logger.warn trace.join("\n") if trace
                error = e
              end

              runs += 1
              break unless error && (max_runs > 0) && (runs < max_runs)
            end

            @finished = true

            if error
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
        yield(@thread)
        synchronize do
          @condition.wait_until { @finished }
        end
        @thread.join
        @thread = nil
      end
    end

    class Generic < Flapjack::Pikelet::Base

     TYPES = ['notifier', 'processor', 'jabber', 'pagerduty', 'oobetet',
              'email', 'sms']

      def start
        super do
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
        super do |thread|
          @pikelet.stop(thread)
        end
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
          @pikelet_class.start if @pikelet_class.respond_to?(:start)
          @server = ::WEBrick::HTTPServer.new(:Port => port, :BindAddress => '127.0.0.1',
            :AccessLog => [], :Logger => WEBrick::Log::new("/dev/null", 7))
          @server.mount "/", Rack::Handler::WEBrick, @pikelet_class
          yield @server  if block_given?
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
        super do |thread|
          @logger.info "shutting down server"
          @server.shutdown
          @logger.info "shut down server"
          @pikelet_class.stop(thread) if @pikelet_class.respond_to?(:stop)
        end
      end
    end

    WRAPPERS = [Flapjack::Pikelet::Generic, Flapjack::Pikelet::HTTP]

    TYPES = {'api'        => [Flapjack::Gateways::API],
             'email'      => [Flapjack::Gateways::Email],
             'notifier'   => [Flapjack::Notifier],
             'processor'  => [Flapjack::Processor],
             'jabber'     => [Flapjack::Gateways::Jabber::Bot,
                              Flapjack::Gateways::Jabber::Notifier,
                              Flapjack::Gateways::Jabber::Interpreter],
             'oobetet'    => [Flapjack::Gateways::Oobetet::Bot,
                              Flapjack::Gateways::Oobetet::Notifier],
             'pagerduty'  => [Flapjack::Gateways::Pagerduty::Notifier,
                              Flapjack::Gateways::Pagerduty::AckFinder],
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
