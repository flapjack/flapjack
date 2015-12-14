#!/usr/bin/env ruby

require 'logger'
require 'syslog'
require 'monitor'

module Flapjack

  class << self
    # Thread and fiber-local

    def configure_log(name, config = {})
      Thread.current[:flapjack_logger_name]   = name
      Thread.current[:flapjack_logger_config] = config
    end

    def logger=(l)
      Thread.current[:flapjack_logger] = l
    end

    def logger
      Thread.current[:flapjack_logger] ||= Flapjack::Logger.new(
        Thread.current[:flapjack_logger_name]   || 'default',
        Thread.current[:flapjack_logger_config] || {}
      )
    end
  end

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
        t = datetime.iso8601(6)
        "#{t} [#{severity}] :: #{@name} :: #{msg}\n"
      end

      output = if config[:file].nil? || config[:file].empty? ||
        !File.exists?(File.dirname(config[:file])) ||
        !File.writable?(File.dirname(config[:file])) ||
        (File.exists?(config[:file]) && !File.writable?(config[:file]))

        STDOUT
      else
        config[:file]
      end

      @logger = ::Logger.new(output)
      @logger.formatter = @formatter

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
      @use_syslog = config.has_key?('syslog_errors') && config['syslog_errors']
    end

    def close
      raise "Already closed" if @logger.nil?
      @logger.close
      @logger = nil
    end

    def self.syslog_add(severity, message, name)
      @lock ||= Monitor.new
      @lock.synchronize do
        level = SYSLOG_LEVELS[severity]
        t = Time.now.iso8601
        l = SEVERITY_LABELS[severity]
        begin
          Syslog.open('flapjack', (Syslog::Constants::LOG_PID | Syslog::Constants::LOG_CONS),
                                   Syslog::Constants::LOG_USER)
          Syslog.mask = Syslog::LOG_UPTO(::Syslog::Constants::LOG_ERR)
          Syslog.log(level, "#{t} [#{l}] :: #{name} :: %s", message)
        ensure
          Syslog.close
        end
      end
    end

    def add(severity, message = nil, progname = nil, &block)
      raise "Cannot log with a closed logger" if @logger.nil?
      @logger.add(severity, message, progname, &block)
      if severity >= @level
        progname ||= 'flapjack'
        if message.nil?
          if block_given?
            message = yield
          else
            message = progname
            progname = 'flapjack'
          end
        end
      end

      Flapjack::Logger.syslog_add(severity, message, @name) if @use_syslog
    end

    LEVELS.each do |level|
      define_method(level) {|progname = nil, &block|
        add(::Logger.const_get(level.upcase), nil, progname, &block)
      }
    end

    def respond_to?(sym)
      (LEVELS + [:configure, :close, :add]).include?(sym)
    end


    ['debug', 'info', 'warn', 'error', 'fatal'].each { |level|
      define_method("#{level}?") {
        @logger.send("#{level}?")
      }
    }

  end

end
