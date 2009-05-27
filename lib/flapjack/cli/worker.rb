#!/usr/bin/env ruby

require 'rubygems'
require 'beanstalk-client'
require 'ostruct'
require 'optparse'
require 'log4r'
require 'log4r/outputter/syslogoutputter'
require 'flapjack/cli/worker'

module Flapjack
  class WorkerOptions
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
 
      # default the port
      options.port ||= 11300
  
      @errors = []
      # check that the host is specified
      unless options.host 
        @errors << "You have to specify a beanstalk host!"
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
 
  class WorkerCLI
    def initialize(opts={})
      @jobs    = Beanstalk::Pool.new(["#{opts[:host]}:#{opts[:port]}"], 'jobs')
      @results = Beanstalk::Pool.new(["#{opts[:host]}:#{opts[:port]}"], 'results')

      @log = Log4r::Logger.new('worker')
      @log.add(Log4r::StdoutOutputter.new('worker'))
      @log.add(Log4r::SyslogOutputter.new('worker'))
    end
    
    def process_loop
      @log.info("Booting main loop...")
      loop do 
        process_check
      end
    end

    def process_check
      # get_check
      @log.debug("Waiting for check...")
      job = @jobs.reserve
      j = YAML::load(job.body)
      @log.info("Processing check id #{j[:id]}")
  
      # perform_check
      command = "sh -c '#{j[:command]}'"
      @log.debug("Executing check: \"#{command}\"")
      result = `#{command}`
      retval = $?.exitstatus

      # report_check
      @log.debug "Reporting results for check id #{j[:id]}."
      @results.yput({:id => j[:id], 
                     :output => result, 
                     :retval => retval.to_i})
     
      # cleanup_check
      # add job back onto stack
      @log.debug("Putting check back onto beanstalk.")
      @jobs.yput(j, 65536, j[:frequency])
        
      # once we're done, clean up
      @log.debug("Deleting job.")
      job.delete
    end
  end

end

