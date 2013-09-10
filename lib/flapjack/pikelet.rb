#!/usr/bin/env ruby

# This class encapsulates the config data and environmental setup used
# by the various Flapjack components.
#
# "In Australia and New Zealand, small pancakes (about 75 mm in diameter) known as pikelets
# are also eaten. They are traditionally served with jam and/or whipped cream, or solely
# with butter, at afternoon tea, but can also be served at morning tea."
#    from http://en.wikipedia.org/wiki/Pancake

require 'monitor'

require 'webrick'

require 'flapjack'

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
      attr_accessor :siblings, :pikelet

      def initialize(pikelet_class, shutdown, opts = {})
        @pikelet_class = pikelet_class

        @config        = opts[:config]
        @logger        = opts[:logger]
        @boot_time     = opts[:boot_time]
        @shutdown      = shutdown

        @siblings      = []

        @lock = Monitor.new
        @stop_condition = @lock.new_cond

        @pikelet = @pikelet_class.new(:lock => @lock,
          :stop_condition => @stop_condition, :config => @config,
          :logger => @logger)

        @finished_condition = @lock.new_cond
      end

      def start(&block)
        @pikelet.siblings = @siblings.map(&:pikelet) if @pikelet.respond_to?(:siblings=)

        @thread = Thread.new do
          Thread.current.abort_on_exception = true

          # TODO rename this, it's only relevant in the error case
          max_runs = @config['max_runs'] || 1
          runs = 0

          keep_running = false
          shutdown_all = false

          loop do
            begin
              @logger.debug "pikelet start for #{@pikelet_class.name}"
              yield
            rescue Flapjack::PikeletStop
              @logger.debug "pikelet exception stop for #{@pikelet_class.name}"
             rescue Flapjack::GlobalStop
              @logger.debug "global exception stop for #{@pikelet_class.name}"
              @shutdown_thread = @thread
              shutdown_all = true
            rescue Exception => e
              @logger.warn "#{e.class.name} #{e.message}"
              trace = e.backtrace
              @logger.warn trace.join("\n") if trace
              runs += 1
              keep_running = (max_runs > 0) && (runs < max_runs)
              shutdown_all = !keep_running
            end

            break unless keep_running
          end

          @lock.synchronize do
            @finished = true
            @finished_condition.signal
          end

          if shutdown_all
            @shutdown.call
          end
        end
      end

      def reload(cfg, &block)
        @logger.configure(cfg['logger'])
        yield
      end

      def stop(&block)
        fin = nil
        @lock.synchronize do
          fin = @finished
        end
        return if fin
        if block_given?
          yield
        else
          case @pikelet.stop_type
          when :exception
            @lock.synchronize do
              @logger.debug "triggering pikelet exception stop for #{@pikelet_class.name}"
              @thread.raise Flapjack::PikeletStop
              @finished_condition.wait_until { @finished }
            end
          when :signal
            @lock.synchronize do
              @logger.debug "triggering pikelet signal stop for #{@pikelet_class.name}"
              @pikelet.instance_variable_set('@should_quit', true)
              @stop_condition.signal
              @finished_condition.wait_until { @finished }
            end
          end
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

    end

    class HTTP < Flapjack::Pikelet::Base

      TYPES = ['web', 'api']

      def start
        @pikelet_class.instance_variable_set('@config', @config)
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
          unless @server.nil?
            @logger.info "shutting down server"
            @server.shutdown
            @logger.info "shut down server"
          end
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

      logger = Flapjack::Logger.new("flapjack-#{type}", config['logger'])

      types = TYPES[type]

      return [] if types.nil?

      created = types.collect {|pikelet_class|
        wrapper = WRAPPERS.detect {|wrap| wrap::TYPES.include?(type) }
        wrapper.new(pikelet_class, shutdown, :config => config,
                    :logger => logger)
      }
      created.each {|c| c.siblings = created - [c] }
      created
    end

  end

end
