#!/usr/bin/env ruby

require 'log4r'
require 'log4r/formatter/patternformatter'
require 'log4r/outputter/consoleoutputters'
require 'log4r/outputter/syslogoutputter'

module Flapjack

  class Logger

    def initialize(name, config = {})
      config ||= {}

      # @name = name

      @log4r_logger = Log4r::Logger.new(name)

      formatter = Log4r::PatternFormatter.new(:pattern => "[%l] %d :: #{name} :: %m",
        :date_pattern => "%Y-%m-%dT%H:%M:%S%z")

      [Log4r::StdoutOutputter, Log4r::SyslogOutputter].each do |outp_klass|
        outp = outp_klass.new(name)
        outp.formatter = formatter
        @log4r_logger.add(outp)
      end

      configure(config)
    end

    def configure(config)
      level = config['level']

      # we'll let Log4r spit the dummy on invalid level values -- but will
      # assume ALL if nothing is provided
      if level.nil? || level.empty?
        level = 'ALL'
      end

      new_level = Log4r.const_get(level.upcase)
      return if @log4r_logger.level.eql?(new_level)

      # puts "setting log level for '#{@name}' to '#{level.upcase}'"
      @log4r_logger.level = new_level
    end

    def method_missing(method, *args, &block)
      @log4r_logger.send(method.to_sym, *args, &block)
    end

    def respond_to?(sym)
      @log4r_logger.respond_to?(sym)
    end

  end

end