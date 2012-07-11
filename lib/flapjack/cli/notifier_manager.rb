#!/usr/bin/env ruby

require 'ostruct'
require 'optparse'

module Flapjack
  class NotifierManagerOptions
    def self.parse(args)
      options = OpenStruct.new
      opts = OptionParser.new do |opts|
        opts.banner = "Usage: flapjack-notifier-manager <command> [options]"
        opts.separator " "
        opts.separator "  where <command> is one of:"
        opts.separator "     start            start a worker"
        opts.separator "     stop             stop all workers"
        opts.separator "     restart          restart workers"
        opts.separator " "
        opts.separator "  and [options] are:"

        opts.on('-b', '--beanstalk HOST', 'location of the beanstalkd') do |host|
          options.host = host
        end
        opts.on('-p', '--port PORT', 'beanstalkd port') do |port|
          options.port = port.to_s
        end
        opts.on('-r', '--recipients FILE', 'recipients file') do |recipients|
          options.recipients = File.expand_path(recipients.to_s)
        end
        opts.on('-c', '--config FILE', 'config file') do |config|
          options.config_filename = config.to_s
        end
      end

      begin
        opts.parse!(args)
      rescue => e
        puts e.message.capitalize + "\n\n"
        puts opts
        exit 1
      end

      # defaults
      options.host ||= "localhost"
      options.port ||= 11300

      @errors = []

      unless ARGV[0] == "stop"
        if options.recipients
          unless File.exists?(options.recipients)
            @errors << "The specified recipients file doesn't exist!"
          end
        else
          @errors << "You must specify a recipients file!"
        end

        if options.config_filename
          unless File.exists?(options.config_filename)
            @errors << "The specified config file dosen't exist!"
          end
        else
          @errors << "You must specify a config file!"
        end
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

      unless %w(start stop restart).include?(args[0])
        puts opts
        exit 1
      end

      options
    end
  end

end
