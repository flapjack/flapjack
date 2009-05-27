#!/usr/bin/env ruby

require 'rubygems'
require 'beanstalk-client'
require 'ostruct'
require 'optparse'
require 'log4r'
require 'log4r/outputter/syslogoutputter'
require 'flapjack/result'

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
 
  class Worker
    
    attr_accessor :jobs, :results, :log

    def initialize(opts={})
      @jobs    = Beanstalk::Pool.new(["#{opts[:host]}:#{opts[:port]}"], 'jobs')
      @results = Beanstalk::Pool.new(["#{opts[:host]}:#{opts[:port]}"], 'results')

      if opts[:logger]
        @log = opts[:logger]
      else
        @log = Log4r::Logger.new('worker')
        @log.add(Log4r::StdoutOutputter.new('worker'))
        @log.add(Log4r::SyslogOutputter.new('worker'))
      end
    end
    
    def process_loop
      @log.info("Booting main loop...")
      loop do 
        process_check
      end
    end

    def process_check
      # get next check off the beanstalk
      job, check = get_check()
  
      # do the actual check
      result, retval = perform_check(check.command)

      # report the results of the check
      report_check(:result => result, :retval => retval, :check => check)
     
      # create another job for the check, delete current job
      cleanup_job(:job => job, :check => check)
    end

    def perform_check(cmd)
      command = "sh -c '#{cmd}'"
      @log.debug("Executing check: \"#{command}\"")
      result = `#{command}`
      retval = $?.exitstatus

      return result, retval
    end

    def report_check(opts={})
      raise ArgumentError unless (opts[:result] && opts[:retval] && opts[:check])

      @log.debug "Reporting results for check id #{opts[:check].id}."
      @results.yput({:id => opts[:check].id, 
                     :output => opts[:result], 
                     :retval => opts[:retval].to_i})
    end

    def cleanup_job(opts={})
      raise ArgumentError unless (opts[:job] && opts[:check])

      # add job back onto stack
      @log.debug("Putting check back onto beanstalk.")
      @jobs.yput(opts[:check], 65536, opts[:check].frequency)
        
      # once we're done, clean up
      @log.debug("Deleting job.")
      opts[:job].delete
    end

    def get_check
      @log.debug("Waiting for check...")
      job = @jobs.reserve
      check = Check.new(YAML::load(job.body))
      @log.info("Got check with id #{check.id}")

      return job, check
    end

  end

end

