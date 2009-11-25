#!/usr/bin/env ruby 

require 'log4r'
require 'log4r/outputter/syslogoutputter'
require File.expand_path(File.join(File.dirname(__FILE__), '..', 'patches'))

module Flapjack
  module Worker
    class Application
     
      # boots the notifier
      def self.run(options={})
        app = self.new(options)
        app.setup_loggers
        app.setup_config
        app.setup_queues

        app
      end

      attr_accessor :log

      def initialize(options={})
        @log = options[:log]
        @notifier_directories = options[:notifier_directories]
        @options = options
      end

      def setup_loggers
        unless @log
	        @log = Log4r::Logger.new("notifier")
	        @log.add(Log4r::StdoutOutputter.new("notifier"))
	        @log.add(Log4r::SyslogOutputter.new("notifier"))
        end
      end

      def setup_config
        @config = OpenStruct.new(@options)
      end

      def setup_queues
        defaults = { :type => :beanstalkd, 
                     :host => 'localhost', 
                     :port => '11300',
                     :log => @log }
        config = defaults.merge(@config.transport || {})
        basedir = config.delete(:basedir) || File.join(File.dirname(__FILE__), '..', 'transports')

        %w(results checks).each do |queue_name|
          
          queue_config = config.merge(:queue_name => queue_name)
       
          class_name = config[:type].to_s.camel_case
          filename = File.join(basedir, "#{config[:type]}.rb")
          
          @log.info("Loading the #{class_name} transport")

          begin 
            require filename
            queue = Flapjack::Transport.const_get("#{class_name}").new(queue_config)
            instance_variable_set("@#{queue_name}_queue", queue)
          rescue LoadError => e
            @log.warning("Attempted to load #{class_name} transport, but it doesn't exist!")
            @log.warning("Exiting.")
            raise # preserves original exception
          end
        end
      end

      def process_check
        @log.info("Waiting for check...")
        check = @checks_queue.next
        @log.info("Processing check with id #{check.check_id}")

        command = "sh -c '#{check.command}'"
        @log.info("Executing check: #{command}")

        output = `#{command}`
        return_value = $?.exitstatus

        @log.info("Sending result.")
        @results_queue.put({:check_id => check.check_id, :output => output, :retval => return_value})
        @log.info("Returning check to transport.")
        @checks_queue.put({:check_id => check.check_id, :command => check.command, :frequency => check.frequency})

        @log.info("Cleaning up check.")
        @checks_queue.delete(check)
      end

      def main
        @log.info("Booting main loop.")
        loop do 
          process_check
        end
      end

    end
  end
end
