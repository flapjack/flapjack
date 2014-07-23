#!/usr/bin/env ruby

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
          puts "flapper is already running."
          exit 1
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
          puts "flapper is not running."
          exit 1
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
          puts "flapper is not running"
          exit 3
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
        raise "bind_port must be an integer" unless bind_port.is_a?(Integer)
        start_every = frequency
        stop_after = frequency.to_f / 2

        begin
          loop do
            begin
              fds = []
              Timeout::timeout(stop_after) do
                puts "#{Time.now}: starting server"

                acceptor = TCPServer.open(bind_ip, bind_port)
                fds = [acceptor]

                while true
                  # puts 'loop'
                  if ios = select(fds, [], [], 10)
                    reads = ios.first
                    # p reads
                    reads.each do |client|
                      if client == acceptor
                        puts 'Someone connected to server. Adding socket to fds.'
                        client, sockaddr = acceptor.accept
                        fds << client
                      elsif client.eof?
                        puts "Client disconnected"
                        fds.delete(client)
                        client.close
                      else
                        # Perform a blocking-read until new-line is encountered.
                        # We know the client is writing, so as long as it adheres to the
                        # new-line protocol, we shouldn't block for very long.
                        # puts "Reading..."
                        data = client.gets("\n")
                        # client.puts(">>you sent: #{data}")
                        if data =~ /quit/i
                          fds.delete(client)
                          client.close
                        end
                      end
                    end
                  end
                end
              end
            rescue Timeout::Error
              puts "#{Time.now}: stopping server"
            ensure
              # should trigger even for an Interrupt
              puts "Cleaning up"
              fds.each {|c| c.close}
            end

            sleep_for = start_every - stop_after
            puts "sleeping for #{sleep_for}"
            sleep(sleep_for)
          end
        rescue Interrupt
          puts "interrupted"
        end
      end

    end
  end
end


desc 'Artificial service that oscillates up and down'
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
