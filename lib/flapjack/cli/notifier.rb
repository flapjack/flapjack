#!/usr/bin/env ruby

require 'ostruct'
require 'optparse'
require 'log4r'
require 'log4r/outputter/syslogoutputter'

module Flapjack
  module Notifier
    class Options
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
          opts.on('-d', '--database-uri URI', 'location of the checks database') do |db|
            options.database_uri = db.to_s
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
  end
 
end
