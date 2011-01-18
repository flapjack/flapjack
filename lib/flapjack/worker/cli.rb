#!/usr/bin/env ruby

require 'ostruct'
require 'optparse'
require 'flapjack/patches'

module Flapjack
  module Worker
    class CLI
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
          opts.on('-c', '--checks-directory DIR', 'sandboxed check directory') do |dir|
            options.checks_directory = dir.to_s
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
        options.host ||= 'localhost'
        options.port ||= 11300
        options.checks_directory ||= File.join(File.dirname(__FILE__), '..', 'checks')

        options
      end
    end
  end
end

