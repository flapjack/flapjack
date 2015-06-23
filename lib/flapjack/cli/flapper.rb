#!/usr/bin/env ruby

require 'socket'

module Flapjack
  module CLI
    class Flapper

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
          exit_now! "No config data found in '#{global_options[:config]}'"
        end
      end

      def start
        puts "flapper starting..."
        main(@options['bind-ip'] || Flapjack::CLI::Flapper.local_ip, @options['bind-port'].to_i, @options[:frequency])
        puts " done."
      end

      private

      module Receiver
        def receive_data(data)
          send_data ">>>you sent: #{data}"
          close_connection if data === /quit/i
        end
      end

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
                  if ios = select(fds, [], [], 10)
                    reads = ios.first
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
                        data = client.gets("\n")
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

desc 'Artificial service that oscillates up and down, for use in http://flapjack.io/docs/2.0/usage/oobetet'
command :flapper do |flapper|

  flapper.flag   [:b, 'bind-ip'],   :desc => 'Override ADDRESS (IPv4 or IPv6) for flapper to bind to'

  flapper.flag   [:P, 'bind-port'], :desc => 'PORT for flapper to bind to (default: 12345)',
    :default_value => '12345'

  flapper.flag   [:f, 'frequency'], :desc => 'oscillate with a frequency of SECONDS [120]',
    :default_value => '120.0'

  flapper.action do |global_options, options, args|
    cli_flapper = Flapjack::CLI::Flapper.new(global_options, options)
    cli_flapper.start
  end

end
