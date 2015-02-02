#!/usr/bin/env ruby

require 'flapjack/coordinator'

module Flapjack
  module CLI
    class Server

      def initialize(global_options, options)
        @global_options = global_options
        @options = options

        @config = Flapjack::Configuration.new
        @config.load(global_options[:config])
        @config_env = @config.all

        if @config_env.nil? || @config_env.empty?
          exit_now! "No config data found in '#{global_options[:config]}'"
        end

        @logfile = case
        when !@options[:logfile].nil?
          @options[:logfile]
        when !@config_env['log_dir'].nil?
          File.join(@config_env['log_dir'], 'flapjack.log')
        else
          "/var/run/flapjack/flapjack.log"
        end
      end

      def start
        print "Flapjack starting..."
        redirect_output(@logfile)
        @coordinator = Flapjack::Coordinator.new(@config)
        return_value = @coordinator.start(:signals => true)
        puts " done."
        exit_now!(return_value) unless return_value.nil?
      end

      private

      # adapted from https://github.com/nesquena/dante/blob/2a5be903fded5bbd44e57b5192763d9107e9d740/lib/dante/runner.rb#L253-L274
      def redirect_output(log_path)
        if log_path.nil?
          # redirect to /dev/null
          # We're not bothering to sync if we're dumping to /dev/null
          # because /dev/null doesn't care about buffered output
          $stdin.reopen '/dev/null'
          $stdout.reopen '/dev/null', 'a'
          $stderr.reopen $stdout
        else
          # if the log directory doesn't exist, create it
          FileUtils.mkdir_p(File.dirname(log_path), :mode => 0755)
          # touch the log file to create it
          FileUtils.touch log_path
          # Set permissions on the log file
          File.chmod(0644, log_path)
          # Reopen $stdout (NOT +STDOUT+) to start writing to the log file
          $stdout.reopen(log_path, 'a')
          # Redirect $stderr to $stdout
          $stderr.reopen $stdout
          $stdout.sync = true
        end
      end

    end
  end
end

desc 'Server for running components (e.g. processor, notifier, gateways)'
command :server do |server|

  server.flag   [:l, 'logfile'],   :desc => 'PATH of the logfile to write to'

  server.action do |global_options,options,args|
    cli_server = Flapjack::CLI::Server.new(global_options, options)
    cli_server.start
  end
end
