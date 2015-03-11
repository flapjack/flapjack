#!/usr/bin/env ruby

require 'dante'

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

        @pidfile = case
        when !@options[:pidfile].nil?
          @options[:pidfile]
        when !@config_env['pid_dir'].nil?
          File.join(@config_env['pid_dir'], 'flapjack.pid')
        else
          "/var/run/flapjack/flapjack.pid"
        end

        @logfile = case
        when !@options[:logfile].nil?
          @options[:logfile]
        when !@config_env['log_dir'].nil?
          File.join(@config_env['log_dir'], 'flapjack.log')
        else
          "/var/run/flapjack/flapjack.log"
        end

        if options[:rbtrace]
          require 'rbtrace'
        end
      end

      def start
        if runner.daemon_running?
          puts "Flapjack is already running."
        else
          print "Flapjack starting..."
          main_umask = nil
          if @options[:daemonize]
            main_umask = File.umask
          else
            print "\n"
          end
          return_value = nil
          runner.execute(:daemonize => @options[:daemonize]) {
            File.umask(main_umask) if @options[:daemonize]
            return_value = start_server
          }
          puts " done."
          exit_now!(return_value) unless return_value.nil?
        end
      end

      def stop
        pid = get_pid
        if runner.daemon_running?
          print "Flapjack stopping..."
          runner.execute(:kill => true)
          puts " done."
        else
          puts "Flapjack is not running."
        end
        exit_now! "Failed to stop Flapjack with pid: #{pid}" unless wait_pid_gone(pid)
      end

      def restart
        pid = get_pid
        if runner.daemon_running?
          print "Flapjack stopping..."
          runner.execute(:kill => true)
          puts " done."
        end
        exit_now! "Failed to stop Flapjack with pid: #{pid}" unless wait_pid_gone(pid)

        @runner = nil

        print "Flapjack starting..."

        main_umask = File.umask
        runner.execute(:daemonize => true) {
          File.umask(main_umask)
          start_server
        }
        puts " done."
      end

      def reload
        if runner.daemon_running?
          pid = get_pid
          print "Reloading Flapjack configuration..."
          begin
            Process.kill('HUP', pid)
            puts " sent HUP to pid #{pid}."
          rescue => e
            puts " couldn't send HUP to pid '#{pid}'."
          end
        else
          exit_now! "Flapjack is not running daemonized."
        end
      end

      def status
        if runner.daemon_running?
          pid = get_pid
          uptime = Time.now - File.stat(@pidfile).ctime
          puts "Flapjack is running: pid #{pid}, uptime #{uptime}"
        else
          exit_now! "Flapjack is not running"
        end
      end

      private

      def runner
        return @runner if @runner

        self.class.skip_dante_traps

        @runner = Dante::Runner.new('flapjack', :pid_path => @pidfile,
          :log_path => @logfile)
        @runner
      end

      def self.skip_dante_traps
        return if Dante::Runner.respond_to?(:orig_start)
        Dante::Runner.send(:alias_method, :orig_start, :start)
        Dante::Runner.send(:define_method, :start) do
          if log_path = options[:log_path] && options[:daemonize].nil?
             redirect_output!
          end

          # skip signal traps
          @startup_command.call(self.options) if @startup_command
        end
      end

      def start_server
        @coordinator = Flapjack::Coordinator.new(@config)
        @coordinator.start(:signals => true)
      end

      def process_exists(pid)
        return unless pid
        begin
          Process.kill(0, pid)
          return true
        rescue Errno::ESRCH
          return false
        end
      end

      # wait until the specified pid no longer exists, or until a timeout is reached
      def wait_pid_gone(pid, timeout = 30)
        print "waiting for a max of #{timeout} seconds for process #{pid} to exit" if process_exists(pid)
        started_at = Time.now.to_i
        while process_exists(pid)
          break unless (Time.now.to_i - started_at < timeout)
          print '.'
          sleep 1
        end
        puts ''
        !process_exists(pid)
      end

      def get_pid
        IO.read(@pidfile).chomp.to_i
      rescue StandardError
        pid = nil
      end

    end
  end
end

desc 'Server for running components (e.g. processor, notifier, gateways)'
command :server do |server|

  server.desc 'Start the server'

  server.command :start do |start|

    start.switch [:d, 'daemonize'], :desc => 'Daemonize',
      :default_value => true

    start.flag   [:p, 'pidfile'],   :desc => 'PATH of the pidfile to write to'

    start.flag   [:l, 'logfile'],   :desc => 'PATH of the logfile to write to'

    start.flag   [:r, 'rbtrace'],   :desc => 'Enable rbtrace profiling'

    start.action do |global_options,options,args|
      server = Flapjack::CLI::Server.new(global_options, options)
      server.start
    end
  end

  server.desc 'Stop the server'
  server.command :stop do |stop|

    stop.flag   [:p, 'pidfile'],   :desc => 'PATH of the pidfile to write to'

    stop.flag   [:l, 'logfile'],   :desc => 'PATH of the logfile to write to'

    stop.action do |global_options,options,args|
      server = Flapjack::CLI::Server.new(global_options, options)
      server.stop
    end
  end

  server.desc 'Restart the server'
  server.command :restart do |restart|

    restart.flag   [:p, 'pidfile'],   :desc => 'PATH of the pidfile to write to'

    restart.flag   [:l, 'logfile'],   :desc => 'PATH of the logfile to write to'

    restart.flag   [:r, 'rbtrace'],   :desc => 'Enable rbtrace profiling'

    restart.action do |global_options,options,args|
      server = Flapjack::CLI::Server.new(global_options, options)
      server.restart
    end
  end

  server.desc 'Reload the server configuration'
  server.command :reload do |reload|

    reload.flag   [:p, 'pidfile'],   :desc => 'PATH of the pidfile to write to'

    reload.flag   [:l, 'logfile'],   :desc => 'PATH of the logfile to write to'

    reload.action do |global_options,options,args|
      server = Flapjack::CLI::Server.new(global_options, options)
      server.reload
    end
  end

  server.desc 'Get server status'
  server.command :status do |status|

    status.flag   [:p, 'pidfile'],   :desc => 'PATH of the pidfile to write to'

    status.flag   [:l, 'logfile'],   :desc => 'PATH of the logfile to write to'

    status.action do |global_options,options,args|
      server = Flapjack::CLI::Server.new(global_options, options)
      server.status
    end
  end

end
