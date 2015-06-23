#!/usr/bin/env ruby

# This class encapsulates the config data and environmental setup used
# by the various Flapjack components.
#
# "In Australia and New Zealand, small pancakes (about 75 mm in diameter) known as pikelets
# are also eaten. They are traditionally served with jam and/or whipped cream, or solely
# with butter, at afternoon tea, but can also be served at morning tea."
#    from http://en.wikipedia.org/wiki/Pancake

# the redis/synchrony gems need to be required in this particular order, see
# the redis-rb README for details
require 'hiredis'
require 'redis/connection/synchrony'
require 'redis'
require 'thin'

require 'flapjack/notifier'
require 'flapjack/processor'
require 'flapjack/gateways/jsonapi'
require 'flapjack/gateways/jabber'
require 'flapjack/gateways/oobetet'
require 'flapjack/gateways/pagerduty'
require 'flapjack/gateways/email'
require 'flapjack/gateways/sms_messagenet'
require 'flapjack/gateways/slack'
require 'flapjack/gateways/sms_twilio'
require 'flapjack/gateways/sms_nexmo'
require 'flapjack/gateways/aws_sns'
require 'flapjack/gateways/web'
require 'flapjack/logger'
require 'thin/version'

module Thin
  # disable Thin's loading of daemons
  # workaround for https://github.com/flapjack/flapjack/issues/133
  def self.win?
    true
  end
end

module Flapjack

  module Pikelet

    # TODO find a better way of expressing these two methods
    def self.is_pikelet?(type)
      type_klass = [Flapjack::Pikelet::Generic,
        Flapjack::Pikelet::Thin].detect do |kl|

        kl::PIKELET_TYPES[type]

      end
      !type_klass.nil?
    end

    def self.create(type, opts = {})
      pikelet = nil
      [Flapjack::Pikelet::Generic,
       Flapjack::Pikelet::Thin].each do |kl|
        next unless kl::PIKELET_TYPES[type]
        break if pikelet = kl.create(type, opts)
      end
      pikelet
    end

    class Base
      attr_reader :type, :status

      def initialize(type, pikelet_class, opts = {})
        @type = type
        @klass = pikelet_class

        @config = opts[:config] || {}
        @redis_config = opts[:redis_config] || {}
        @boot_time = opts[:boot_time]
        @coordinator = opts[:coordinator]

        @logger = Flapjack::Logger.new("flapjack-#{type}", @config['logger'])

        @status = 'initialized'
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

     PIKELET_TYPES = {'notifier'   => Flapjack::Notifier,
                      'processor'  => Flapjack::Processor,
                      'jabber'     => Flapjack::Gateways::Jabber,
                      'pagerduty'  => Flapjack::Gateways::Pagerduty,
                      'oobetet'    => Flapjack::Gateways::Oobetet,
                      'email'      => Flapjack::Gateways::Email,
                      'sms'        => Flapjack::Gateways::SmsMessagenet,
                      'slack'      => Flapjack::Gateways::Slack,
                      'sms_twilio' => Flapjack::Gateways::SmsTwilio,
                      'sms_nexmo'  => Flapjack::Gateways::SmsNexmo,
                      'sns'        => Flapjack::Gateways::AwsSns}

      def self.create(type, opts = {})
        self.new(type, PIKELET_TYPES[type], :config => opts[:config],
          :redis_config => opts[:redis_config],
          :boot_time => opts[:boot_time],
          :coordinator => opts[:coordinator])
      end

      def initialize(type, pikelet_klass, opts = {})
        super(type, pikelet_klass, opts)

        @pikelet = @klass.new(opts.merge(:logger => @logger))
      end

      def start
        @fiber = Fiber.new {
          @pikelet.start
        }
        super
        @fiber.resume
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

      PIKELET_TYPES = {'web'     => Flapjack::Gateways::Web,
                       'jsonapi' => Flapjack::Gateways::JSONAPI}

      def self.create(type, opts = {})
        ::Thin::Logging.silent = true
        self.new(type, PIKELET_TYPES[type], :config => opts[:config],
          :redis_config => opts[:redis_config],
          :boot_time => opts[:boot_time])
      end

      def initialize(type, pikelet_klass, opts = {})
        super(type, pikelet_klass, opts)

        pikelet_klass.instance_variable_set('@config', @config)
        pikelet_klass.instance_variable_set('@redis_config', @redis_config)
        pikelet_klass.instance_variable_set('@logger', @logger)

        if @config
          @bind_address = @config['bind_address']
          @port = @config['port']
          @port = @port.nil? ? nil : @port.to_i
          @timeout = @config['timeout']
          @timeout = @timeout.nil? ? 300 : @timeout.to_i
        end
        @bind_address = '0.0.0.0' if @bind_address.nil?
        @port = 3001 if (@port.nil? || @port <= 0 || @port > 65535)

        @server = ::Thin::Server.new(@bind_address, @port,
                    @klass, :signals => false)
        @server.timeout = @timeout
      end

      def start
        super
        @klass.start if @klass.respond_to?(:start)
        @server.start
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

  end

end
