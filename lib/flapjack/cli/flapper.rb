#!/usr/bin/env ruby

require 'eventmachine'
require 'socket'
require 'dante'

module Flapjack
  module CLI
    class Flapper

      def self.local_ip
        # turn off reverse DNS resolution temporarily
        orig, Socket.do_not_reverse_lookup = Socket.do_not_reverse_lookup, true

        begin
          UDPSocket.open do |s|
            s.connect '64.233.187.99', 1
            s.addr.last
          end
        rescue Errno::ENETUNREACH => e
          '127.0.0.1'
        end
      ensure
        Socket.do_not_reverse_lookup = orig
      end

      def initialize(global_options, options)
        @global_options = global_options
        @options = options

        if @global_options[:'force-utf8']
          Encoding.default_external = 'UTF-8'
          Encoding.default_internal = 'UTF-8'
        end

        @config = Flapjack::Configuration.new
        @config.load(global_options[:config])
        @config_env = @config.all

        if @config_env.nil? || @config_env.empty?
          exit_now! "No config data for environment '#{FLAPJACK_ENV}' found in '#{global_options[:config]}'"
        end

        @pidfile = case
        when !@options[:pidfile].nil?
          @options[:pidfile]
        when !@config_env['pid_dir'].nil?
          File.join(@config_env['pid_dir'], 'flapper.pid')
        else
          "/var/run/flapjack/flapper.pid"
        end

        @logfile = case
        when !@options[:logfile].nil?
          @options[:logfile]
        when !@config_env['log_dir'].nil?
          File.join(@config_env['log_dir'], 'flapper.log')
        else
          "/var/run/flapjack/flapper.log"
        end
      end

      def start
        if runner.daemon_running?
          puts "flapper is already running."
        else
          print "flapper starting..."
          main_umask = nil
          if @options[:daemonize]
            main_umask = File.umask
          else
            print "\n"
          end
          runner.execute(:daemonize => @options[:daemonize]) do
            File.umask(main_umask) if @options[:daemonize]
            main(@options['bind-ip'] || Flapjack::CLI::Flapper.local_ip, @options['bind-port'].to_i, @options[:frequency])
          end
          puts " done."
        end
      end

      def stop
        pid = get_pid
        if runner.daemon_running?
          print "flapper stopping..."
          runner.execute(:kill => true)
          puts " done."
        else
          puts "flapper is not running."
        end
        exit_now! unless wait_pid_gone(pid)
      end

      def restart
        print "flapper restarting..."
        main_umask = File.umask
        runner.execute(:daemonize => true, :restart => true) do
          File.umask(main_umask)
          main(@options['bind-ip'], @options['bind-port'].to_i, @options[:frequency])
        end
        puts " done."
      end

      def status
        if runner.daemon_running?
          pid = get_pid
          uptime = Time.now - File.stat(@pidfile).ctime
          puts "flapper is running: pid #{pid}, uptime #{uptime}"
        else
          exit_now! "flapper is not running"
        end
      end

      private

      module Receiver
        def receive_data(data)
          send_data ">>>you sent: #{data}"
          close_connection if data === /quit/i
        end
      end

      def runner
        return @runner if @runner

        @runner = Dante::Runner.new('flapper', :pid_path => @pidfile,
          :log_path => @logfile)
        @runner
      end

      def main(bind_ip, bind_port, frequency)
        raise "bind_port must be an integer" unless bind_port.is_a?(Integer) && (bind_port > 0)
        start_every = frequency
        stop_after  = frequency.to_f / 2

        EM.run do

          puts "#{Time.now}: starting server on #{bind_ip}:#{bind_port}"
          server_init = EM.start_server bind_ip, bind_port, Flapjack::CLI::Flapper::Receiver
          EM.add_timer(stop_after) do
            puts "#{Time.now}: stopping server"
            EM.stop_server(server_init)
          end

          EM.add_periodic_timer(start_every) do
            puts "#{Time.now}: starting server on #{bind_ip}:#{bind_port}"
            server = EM.start_server bind_ip, bind_port, Flapjack::CLI::Flapper::Receiver
            EM.add_timer(stop_after) do
              puts "#{Time.now}: stopping server"
              EM.stop_server(server)
            end
          end
        end
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


desc 'Artificial service that oscillates up and down, for use in http://flapjack.io/docs/1.0/usage/oobetet'
command :flapper do |flapper|

  flapper.desc 'start flapper'
  flapper.command :start do |start|

    start.switch [:d, 'daemonize'], :desc => 'Daemonize',
      :default_value => true

    start.flag   [:p, 'pidfile'],   :desc => 'PATH of the pidfile to write to'

    start.flag   [:l, 'logfile'],   :desc => 'PATH of the logfile to write to'

    start.flag   [:b, 'bind-ip'],   :desc => 'Override ADDRESS (IPv4 or IPv6) for flapper to bind to'

    start.flag   [:P, 'bind-port'], :desc => 'PORT for flapper to bind to (default: 12345)',
      :default_value => '12345'

    start.flag   [:f, 'frequency'], :desc => 'oscillate with a frequency of SECONDS [120]',
      :default_value => '120.0'

    start.action do |global_options, options, args|
      cli_flapper = Flapjack::CLI::Flapper.new(global_options, options)
      cli_flapper.start
    end
  end

  flapper.desc 'stop flapper'
  flapper.command :stop do |stop|

    stop.flag   [:p, 'pidfile'],   :desc => 'PATH of the pidfile to write to'

    stop.flag   [:l, 'logfile'],   :desc => 'PATH of the logfile to write to'

    stop.action do |global_options, options, args|
      cli_flapper = Flapjack::CLI::Flapper.new(global_options, options)
      cli_flapper.stop
    end
  end

  flapper.desc 'restart flapper'
  flapper.command :restart do |restart|

    restart.flag   [:p, 'pidfile'],   :desc => 'PATH of the pidfile to write to'

    restart.flag   [:l, 'logfile'],   :desc => 'PATH of the logfile to write to'

    restart.flag   [:b, 'bind-ip'],   :desc => 'Override ADDRESS (IPv4 or IPv6) for flapper to bind to'

    restart.flag   [:P, 'bind-port'], :desc => 'PORT for flapper to bind to (default: 12345)',
      :default_value => 12345

    restart.flag   [:f, 'frequency'], :desc => 'oscillate with a frequency of SECONDS [120]',
      :default_value => 120.0

    restart.action do |global_options, options, args|
      cli_flapper = Flapjack::CLI::Flapper.new(global_options, options)
      cli_flapper.restart
    end
  end

  flapper.desc 'flapper status'
  flapper.command :status do |status|

    status.flag   [:p, 'pidfile'],   :desc => 'PATH of the pidfile to write to'

    status.flag   [:l, 'logfile'],   :desc => 'PATH of the logfile to write to'

    status.action do |global_options, options, args|
      cli_flapper = Flapjack::CLI::Flapper.new(global_options, options)
      cli_flapper.status
    end
  end
end
