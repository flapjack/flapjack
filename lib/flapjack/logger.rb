#!/usr/bin/env ruby

require 'logger'
require 'syslog'

begin
  # Ruby 2.0+
  require 'syslog/logger'
rescue LoadError
end

module Flapjack

  class Logger

    LEVELS = [:debug, :info, :warn, :error, :fatal]

    SEVERITY_LABELS = %w(DEBUG INFO WARN ERROR FATAL)

    SYSLOG_LEVELS = [::Syslog::Constants::LOG_DEBUG,
                     ::Syslog::Constants::LOG_INFO,
                     ::Syslog::Constants::LOG_WARNING,
                     ::Syslog::Constants::LOG_ERR,
                     ::Syslog::Constants::LOG_CRIT
                    ]

    def initialize(name, config = {})
      config ||= {}

      @name = name

      @formatter = proc do |severity, datetime, progname, msg|
        t = datetime.iso8601
        "#{t} [#{severity}] :: #{name} :: #{msg}\n"
      end

      @syslog_formatter = proc do |severity, datetime, progname, msg|
        t = datetime.iso8601
        l = SEVERITY_LABELS[severity]
        "#{t} [#{l}] :: #{name} :: #{msg}\n"
      end

      @logger = ::Logger.new(STDOUT)
      @logger.formatter = @formatter

      if Syslog.const_defined?('Logger', false)
        # Ruby 2.0+
        @sys_logger = Syslog.const_get('Logger', false).new('flapjack')
        @sys_logger.formatter = @syslog_formatter
      end

      configure(config)
    end

    def configure(config)
      raise "Cannot configure closed logger" if @logger.nil?

      level = config['level']

      # we'll let Logger spit the dummy on invalid level values -- but will
      # assume INFO if nothing is provided
      if level.nil? || level.empty?
        level = 'INFO'
      end

      err = nil

      @level = begin
        ::Logger.const_get(level.upcase)
      rescue NameError
        err = "Unknown Logger severity level '#{level.upcase}', using INFO..."
        ::Logger::INFO
      end

      @logger.error(err) if err

      @logger.level = @level
      if @sys_logger
        @sys_logger.level = @level
      end
    end

    def close
      raise "Already closed" if @logger.nil?
      @logger.close
      @logger = nil
      if @sys_logger
        @sys_logger.close
        @sys_logger = nil
      end
    end

    def add(severity, message = nil, progname = nil, &block)
      raise "Cannot log with a closed logger" if @logger.nil?
      @logger.add(severity, message, progname, &block)
      return if severity < @level

      progname ||= 'flapjack'
      if message.nil?
        if block_given?
          message = yield
        else
          message = progname
          progname = 'flapjack'
        end
      end

      if @sys_logger
        @sys_logger.add(severity, message, progname, &block)
      else
        level = SYSLOG_LEVELS[severity]
        t = Time.now.iso8601
        l = SEVERITY_LABELS[severity]
        begin
          Syslog.open('flapjack', (Syslog::Constants::LOG_PID | Syslog::Constants::LOG_CONS),
                                   Syslog::Constants::LOG_USER)
          Syslog.mask = Syslog::LOG_UPTO(level)
          Syslog.log(level, "#{t} [#{l}] :: #{@name} :: %s", message)
        ensure
          Syslog.close
        end
      end
    end

    LEVELS.each do |level|
      define_method(level) {|progname, &block|
        add(::Logger.const_get(level.upcase), nil, progname, &block)
      }
    end

    def respond_to?(sym)
      (LEVELS + [:configure, :close, :add]).include?(sym)
    end

    def method_missing(method, *args, &block)
      @logger.send(method.to_sym, *args, &block)

      # if Syslog.const_defined?('Logger', false)
      #   # Ruby 2.0+
      #   @sys_logger.send(method.to_sym, *args, &block)
      # else
      #   # Ruby 1.9
      #   @syslog.send(method.to_sym, *args, &block)
      # end
    end

  end

end
