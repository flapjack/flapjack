#!/usr/bin/env ruby 

$: << File.expand_path(File.join(File.dirname(__FILE__), '..', '..'))
require 'log4r'
require 'log4r/outputter/syslogoutputter'
require 'flapjack/patches'
require 'flapjack/notifier_engine'

module Flapjack
  module Notifier
    class Application
     
      # boots the notifier
      def self.run(options={})
        app = self.new(options)
        app.setup_config
        app.setup_loggers
        app.setup_notifiers
        app.setup_notifier_engine
        app.setup_recipients
        app.setup_persistence
        app.setup_queues
        app.setup_filters

        app
      end

      attr_accessor :log, :recipients

      def initialize(options={})
        @log = options[:log]
        @notifier_directories = options[:notifier_directories]
        @filter_directories = options[:filter_directories]
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

      def setup_notifiers
        @notifier_directories ||= []

        default_directory = File.expand_path(File.join(File.dirname(__FILE__), '..', 'notifiers'))
        # the default directory should be the last in the list
        if @notifier_directories.include?(default_directory)
          @notifier_directories << @notifier_directories.delete(default_directory)
        else
          @notifier_directories << default_directory
        end
     
        # filter to the directories that actually exist
        @notifier_directories = @notifier_directories.find_all do |dir|
          if File.exists?(dir)
            true
          else
            @log.warning("Notifiers directory #{dir} doesn't exist. Skipping.")
            false
          end
        end

        @notifiers = []
      
        # load up the notifiers and pass a config
        @config.notifiers.each_pair do |notifier, config|
          filenames = @notifier_directories.map {|dir| File.join(dir, notifier.to_s, 'init' + '.rb')}
          filename = filenames.find {|filename| File.exists?(filename)}

          if filename
            @log.info("Loading the #{notifier.to_s.capitalize} notifier (from #{filename})")
            require filename
            config.merge!(:log => @log)
            notifier = Flapjack::Notifiers.const_get("#{notifier.to_s.capitalize}").new(config)
            @notifiers << notifier
          else
            @log.warning("Flapjack::Notifiers::#{notifier.to_s.capitalize} doesn't exist!")
          end
        end

      end

      def setup_notifier_engine
        options = { :log => @log, :notifiers => @notifiers }
        @notifier_engine = Flapjack::NotifierEngine.new(options)
      end

      def setup_recipients
        @recipients ||= []
     
        @recipients += (@config.recipients || [])
        # so poking at a recipient within notifiers is easier
        @recipients.map! do |recipient|
          OpenStruct.new(recipient)
        end
      end

      def setup_persistence
        defaults = { :backend => :data_mapper,
                     :log => @log }
        config = defaults.merge(@config.persistence || {})
        basedir = config.delete(:basedir) || File.join(File.dirname(__FILE__), '..', 'persistence')
       
        filename = File.join(basedir, "#{config[:backend]}.rb")
        class_name = config[:backend].to_s.camel_case

        @log.info("Loading the #{class_name} persistence backend")
        
        begin 
          require filename
          @persistence = Flapjack::Persistence.const_get(class_name).new(config)
        rescue LoadError => e
          @log.warning("Attempted to load #{class_name} persistence backend, but it doesn't exist!")
          @log.warning("Exiting.")
          raise # preserves original exception
        end

      end

      def setup_queues
        defaults = { :backend => :beanstalkd, 
                     :host => 'localhost', 
                     :port => '11300',
                     :queue_name => 'results',
                     :log => @log }
        config = defaults.merge(@config.transport || {})
        basedir = config.delete(:basedir) || File.join(File.dirname(__FILE__), '..', 'transports')

        class_name = config[:backend].to_s.camel_case
        filename = File.join(basedir, "#{config[:backend]}.rb")

        @log.info("Loading the #{class_name} transport")
      
        begin 
          require filename
          @results_queue = Flapjack::Transport.const_get(class_name).new(config)
        rescue LoadError => e
          @log.warning("Attempted to load #{class_name} transport, but it doesn't exist!")
          @log.warning("Exiting.")
          raise # preserves original exception
        end
      end

      def setup_filters 
        @filter_directories ||= []

        default_directory = File.expand_path(File.join(File.dirname(__FILE__), '..', 'filters'))
        # the default directory should be the last in the list
        if @filter_directories.include?(default_directory)
          @filter_directories << @filter_directories.delete(default_directory)
        else
          @filter_directories << default_directory
        end
     
        # filter to the directories that actually exist
        @filter_directories = @filter_directories.find_all do |dir|
          if File.exists?(dir)
            true
          else
            @log.warning("Filters directory #{dir} doesn't exist. Skipping.")
            false
          end
        end

        @filters = []

        @config.filters.each do |filter|
          filenames = @filter_directories.map {|dir| File.join(dir, filter.to_s + '.rb')}
          filename = filenames.find {|filename| File.exists?(filename)}

          if filename 
            @log.info("Loading the #{filter.camel_case} filter (from #{filename})")
            require filename
            filter = Flapjack::Filters.const_get(filter.camel_case).new(:log => @log, :persistence => @persistence)
            @filters << filter
          else
            @log.warning("Flapjack::Filters::#{filter.camel_case} doesn't exist!")
          end
        end
        
      end

      def process_result
        @log.debug("Waiting for new result...")
        result = @results_queue.next # this blocks until a result is popped
        
        @log.info("Processing result for check #{result.check_id}.")
        event = @persistence.create_event(result)
       

        block = @filters.find {|filter| filter.block?(result) }
        unless block
          # do munging
          @notifier_engine.notify!(:result => result, 
                                   :event => event, 
                                   :recipients => recipients)
        end

        @log.info("Storing status of check.")
        @persistence.save(result)

        @log.info("Deleting result for check #{result.check_id}.")
        @results_queue.delete(result)
      end

      def main
        @log.info("Booting main loop.")
        loop do 
          process_result
        end
      end

    end
  end
end
