#!/usr/bin/env ruby

require 'flapjack/coordinator'

module Flapjack
  module CLI
    class Server

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
        puts "Flapjack starting..."
        @coordinator = Flapjack::Coordinator.new(@config)
        return_value = @coordinator.start(:signals => true)
        puts " done."
        exit_now!(return_value) unless return_value.nil?
      end

    end
  end
end

desc 'Server for running components (e.g. processor, notifier, gateways)'
command :server do |server|
  server.action do |global_options,options,args|
    cli_server = Flapjack::CLI::Server.new(global_options, options)
    cli_server.start
  end
end
