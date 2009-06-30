#!/usr/bin/env ruby

require 'rubygems'
require 'ostruct'
require 'optparse'
require 'log4r'
require 'log4r/outputter/syslogoutputter'

module Flapjack
  class NotifierOptions
    def self.parse(args)
      options = OpenStruct.new
      opts = OptionParser.new do |opts|
        # the available command line options
        opts.on('-b', '--beanstalk HOST', 'location of the beanstalkd') do |host|
          options.host = host
        end
        opts.on('-p', '--port PORT', 'beanstalkd port') do |port|
          options.port = port.to_i
        end
        opts.on('-r', '--recipients FILE', 'recipients file') do |recipients|
          options.recipients = recipients.to_s
        end
        opts.on('-c', '--config FILE', 'config file') do |config|
          options.config_filename = config.to_s
        end
        opts.on_tail("-h", "--help", "Show this message") do
          puts opts
          exit
        end
      end

      # parse the options
      begin
        opts.parse!(args)
      rescue OptionParser::MissingArgument => e
        # if an --option is missing it's argument
        puts e.message.capitalize + "\n\n"
        puts opts
        exit 1
      end
 
      # default the host + port
      options.host ||= 'localhost'
      options.port ||= 11300
  
      @errors = []
      # check that recipients file exists
      if options.recipients
        unless File.exists?(options.recipients.to_s)
          @errors << "The specified recipients file doesn't exist!"
        end
      else
        @errors << "You need to specify a recipients file with [-r|--recipients]."
      end

      # check that config file exists
      if options.config_filename 
        unless File.exists?(options.config_filename.to_s)
          @errors << "The specified config file doesn't exist!"
        end
      else
        options.config_filename ||= "/etc/flapjack/flapjack-notifier.yaml"
        unless File.exists?(options.config_filename.to_s)
          @errors << "The default config file (#{options.config_filename}) doesn't exist!"
          @errors << "Set one up, or specify one with [-c|--config]."
        end
      end

      # if there are errors, print them out and exit
      if @errors.size > 0
        puts "Errors:"
        @errors.each do |error|
          puts "  - #{error}"
        end
        puts
        puts opts
        exit 2
      end
  
      options
    end
  end
  
  class NotifierCLI
    attr_accessor :log, :recipients, :results_queue, :config
    attr_accessor :notifier, :notifiers
    attr_accessor :condition
  
    def initialize(opts={})
      @log = opts[:logger]
      @log ||= Log4r::Logger.new("notifier")
    end
  
    def setup_loggers
      @log.add(Log4r::StdoutOutputter.new('notifier'))
      @log.add(Log4r::SyslogOutputter.new('notifier'))
    end
  
    def setup_recipients(opts={})
  
      if opts[:yaml]
        yaml = opts[:yaml]
      else
        opts[:filename] ||= File.join(Dir.pwd, "recipients.yaml")
        yaml = YAML::load(File.read(opts[:filename]))
      end
 
      # FIXME: add error detection for passing in dumb things

      @recipients = yaml.map do |r|
        OpenStruct.new(r)
      end
    end

    def setup_config(opts={})
      if opts[:yaml]
        yaml = opts[:yaml]
      else
        opts[:filename] ||= File.join(Dir.pwd, "flapjack-notifier.yaml")
        yaml = YAML::load(File.read(opts[:filename]))
      end

      @config = OpenStruct.new(yaml)
    end

    def initialize_notifiers(opts={})
      notifiers_directory = opts[:notifiers_directory] 
      notifiers_directory ||= File.expand_path(File.join(File.dirname(__FILE__), '..', 'notifiers'))

      raise ArgumentError, "notifiers directory doesn't exist!" unless File.exists?(notifiers_directory)
      
      @notifiers = []
     
      @config.notifiers.each_pair do |notifier, config|
        filename = File.join(notifiers_directory, notifier.to_s, 'init')
        if File.exists?(filename + '.rb')
          @log.debug("Loading the #{notifier.to_s.capitalize} notifier")
          require filename
          @notifiers << Flapjack::Notifiers.const_get("#{notifier.to_s.capitalize}").new(config)
        else
          @log.warning("Flapjack::Notifiers::#{notifier.to_s.capitalize} doesn't exist!") 
        end
      end

      @notifiers
    end

    # Sets up notifier to do the grunt work of notifying people when checks 
    # return badly. 
    #
    # Accepts a list of recipients (:recipients) and a logger (:logger) as 
    # arguments. If neither of these are specified, it will default to an 
    # existing list of recipients and the current logger.
    #
    # Sets up and returns @notifier, an instance of Flapjack::Notifier
    def setup_notifier(opts={})
      recipients = (opts[:recipients] || @recipients)
      log = (opts[:logger] || @log)
      initialize_notifiers
      notifiers = @notifiers # should we accept a list of notifiers?
      @notifier = Flapjack::Notifier.new(:logger => log,
                                         :notifiers => notifiers,
                                         :recipients => recipients)
    end
  
    def process_loop
      @log.info("Processing results...")
      loop do
        process_result
      end
    end
  
    def process_result
      @log.debug("Waiting for new result...")
      result_job = @results_queue.reserve
      result = Result.new(YAML::load(result_job.body))
      
      @log.info("Processing result for check '#{result.id}'")
      if result.warning? || result.critical?
        @log.info("Notifying on check '#{result.id}'")
        @notifier.notify!(result)
      end

      @log.debug("Deleting result for check '#{result.id}' from queue")
      result_job.delete
    end
  
  end
  
end
