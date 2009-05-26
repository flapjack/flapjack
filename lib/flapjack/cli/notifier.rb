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
        opts.on('-r', '--recipients FILE', 'recipients file') do |recipients|
          options.recipients = recipients.to_s
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
  
      @errors = []
      # check that the host is specified
      unless options.host 
        @errors << "You have to specify a beanstalk host!"
      end
  
      # check that recipients file exists
      unless File.exists?(options.recipients.to_s)
        @errors << "You have to specify a recipients file!"
      end
  
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
    attr_accessor :log, :recipients, :notifier, :results_queue
    attr_accessor :condition
  
    def initialize
      @log = Log4r::Logger.new("notifier")
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
  
      @recipients = yaml.map do |r|
        OpenStruct.new(r)
      end
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
