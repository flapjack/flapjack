#!/usr/bin/env ruby

require 'logger'

begin
  # Ruby 2.0+
  require 'syslog/logger'
rescue LoadError
  # Ruby 1.9
  require 'syslog'
end

module Flapjack

  class Logger

    LEVELS = [:debug, :info, :warn, :error, :fatal]

    # only used for 1.9
    SYSLOG_LEVELS_MAP = {
      :debug  => Syslog::Constants::LOG_DEBUG,
      :info   => Syslog::Constants::LOG_INFO,
      :warn   => Syslog::Constants::LOG_WARNING,
      :error  => Syslog::Constants::LOG_ERR,
      :fatal  => Syslog::Constants::LOG_CRIT
    }

    def initialize(name, config = {})
      config ||= {}

      @name = name

      @formatter = proc do |severity, datetime, progname, msg|
        "#{datetime.iso8601} [#{severity}] :: #{name} :: #{msg}\n"
      end

      @logger = ::Logger.new(STDOUT)
      @logger.formatter = @formatter

      if Syslog.const_defined?('Logger', false)
        # Ruby 2.0+
        @sys_logger = Syslog.const_get('Logger', false).new('flapjack')
        @sys_logger.formatter = @formatter
      else
        # Ruby 1.9
        @syslog = Syslog.opened? ? Syslog :
                    Syslog.open('flapjack',
                                (Syslog::Constants::LOG_PID | Syslog::Constants::LOG_CONS),
                                Syslog::Constants::LOG_USER)
      end

      configure(config)
    end

    def configure(config)
      level = config['level']

      # we'll let Logger spit the dummy on invalid level values -- but will
      # assume INFO if nothing is provided
      if level.nil? || level.empty?
        level = 'INFO'
      end

      err = nil

      new_level = begin
        ::Logger.const_get(level.upcase)
      rescue NameError
        err = "Unknown Logger severity level '#{level.upcase}', using INFO..."
        ::Logger::INFO
      end

      @logger.error(err) if err

      @logger.level = new_level
      if @sys_logger
        @sys_logger.level = new_level
      elsif @syslog
        Syslog.mask = Syslog::LOG_UPTO(SYSLOG_LEVELS_MAP[level.downcase.to_sym])
      end

    end

    LEVELS.each do |level|
      define_method(level) {|*args, &block|
        @logger.send(level.to_sym, *args, &block)
        if @sys_logger
          @sys_logger.send(level.to_sym, *args, &block)
        elsif @syslog
          t = Time.now.iso8601
          l = level.to_s.upcase
          @syslog.log(SYSLOG_LEVELS_MAP[level],
                      "#{t} [#{l}] :: #{@name} :: %s",
                      (block ? block.call : args.first))
        end
      }
    end

    def respond_to?(sym)
      (LEVELS + [:configure]).include?(sym)
    end

  end

end
