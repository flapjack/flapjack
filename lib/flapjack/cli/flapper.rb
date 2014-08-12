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

        UDPSocket.open do |s|
          s.connect '64.233.187.99', 1
          s.addr.last
        end
      ensure
        Socket.do_not_reverse_lookup = orig
      end

      def initialize(global_options, options)
        @global_options = global_options
        @options = options
      end

      def start
        if runner.daemon_running?
          exit_now! "flapper is already running."
        else
          print "flapper starting..."
          runner.execute(:daemonize => @options[:daemonize]) do
            main(@options['bind-ip'], @options['bind-port'].to_i, @options[:frequency])
          end
          puts " done."
        end
      end

      def stop
        if runner.daemon_running?
          print "flapper stopping..."
          runner.execute(:kill => true)
          puts " done."
        else
          exit_now! "flapper is not running."
        end
      end

      def restart
        print "flapper restarting..."
        runner.execute(:daemonize => true, :restart => true) do
          main(@options['bind-ip'], @options['bind-port'].to_i, @options[:frequency])
        end
        puts " done."
      end

      def status
        uptime = (runner.daemon_running?) ? (Time.now - File.stat(@options[:pidfile]).ctime) : 0
        if runner.daemon_running?
          puts "flapper is running: #{uptime}"
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

        @runner = Dante::Runner.new('flapper', :pid_path => @options[:pidfile],
          :log_path => @options[:logfile])
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

    end
  end
end


desc 'Artificial service that oscillates up and down, for use in http://flapjack.io/docs/1.0/usage/oobetet'
command :flapper do |flapper|

  flapper.desc 'start flapper'
  flapper.command :start do |start|

    start.switch [:d, 'daemonize'], :desc => 'Daemonize',
      :default_value => true

    start.flag   [:p, 'pidfile'],   :desc => 'PATH of the pidfile to write to',
      :default_value =>  "/var/run/flapjack/flapper.pid"

    start.flag   [:l, 'logfile'],   :desc => 'PATH of the logfile to write to',
      :default_value =>  "/var/log/flapjack/flapper.log"

    start.flag   [:b, 'bind-ip'],   :desc => 'ADDRESS (IPv4 or IPv6) for flapper to bind to',
      :default_value => Flapjack::CLI::Flapper.local_ip

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

    stop.flag   [:p, 'pidfile'],   :desc => 'PATH of the pidfile to write to',
      :default_value =>  "/var/run/flapjack/flapper.pid"

    stop.flag   [:l, 'logfile'],   :desc => 'PATH of the logfile to write to',
      :default_value =>  "/var/log/flapjack/flapper.log"

    stop.action do |global_options, options, args|
      cli_flapper = Flapjack::CLI::Flapper.new(global_options, options)
      cli_flapper.stop
    end
  end

  flapper.desc 'restart flapper'
  flapper.command :restart do |restart|

    restart.flag   [:p, 'pidfile'],   :desc => 'PATH of the pidfile to write to',
      :default_value =>  "/var/run/flapjack/flapper.pid"

    restart.flag   [:l, 'logfile'],   :desc => 'PATH of the logfile to write to',
      :default_value =>  "/var/log/flapjack/flapper.log"

    restart.flag   [:b, 'bind-ip'],   :desc => 'ADDRESS (IPv4 or IPv6) for flapper to bind to',
      :default_value => Flapjack::CLI::Flapper.local_ip

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

    status.flag   [:p, 'pidfile'],   :desc => 'PATH of the pidfile to write to',
      :default_value =>  "/var/run/flapjack/flapper.pid"

    status.flag   [:l, 'logfile'],   :desc => 'PATH of the logfile to write to',
      :default_value =>  "/var/log/flapjack/flapper.log"

    status.action do |global_options, options, args|
      cli_flapper = Flapjack::CLI::Flapper.new(global_options, options)
      cli_flapper.status
    end
  end
end
