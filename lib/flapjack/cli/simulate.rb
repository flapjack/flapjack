#!/usr/bin/env ruby

require 'redis'

require 'flapjack/configuration'
require 'flapjack/data/event'

module Flapjack
  module CLI
    class Simulate

      def initialize(global_options, options)
        @global_options = global_options
        @options = options

        if @global_options[:'force-utf8']
          Encoding.default_external = 'UTF-8'
          Encoding.default_internal = 'UTF-8'
        end

        config = Flapjack::Configuration.new
        config.load(global_options[:config])
        @config_env = config.all

        if @config_env.nil? || @config_env.empty?
          exit_now! "No config data found in '#{global_options[:config]}'"
        end

        Flapjack::RedisProxy.config = config.for_redis
        Zermelo.redis = Flapjack.redis
      end

      def _fail
        events(:state => @options[:state], :recover => false,
          :check => @options[:check], :minutes => @options[:time].to_f,
          :interval => @options[:interval].to_f)
      end

      def fail_and_recover
        events(:state => @options[:state], :recover => true,
          :check => @options[:check], :minutes => @options[:time].to_f,
          :interval => @options[:interval].to_f)
      end

      def ok
        events(:state => 'ok', :recover => false,
          :check => @options[:check], :minutes => @options[:time].to_f,
          :interval => @options[:interval].to_f)
      end

      private

      def events(opts = {})
        stop_after = (opts[:minutes] * 60).to_i
        recover = opts[:recover]
        state = opts[:state] || 'critical'
        event = {
          'check'  => opts[:check] || 'HTTP',
          'type'   => 'service'
        }
        failure  = event.merge('state' => state, 'summary' => 'Simulated check output (test by operator)')
        recovery = event.merge('state' => 'ok', 'summary' => 'Simulated check output (test by operator)')
        key = event['check']

        lock = Monitor.new
        stop_cond = lock.new_cond
        @finish = false

        failer = Thread.new do
          fin = nil

          loop do
            lock.synchronize do
              unless fin = @finish
                puts "#{Time.now}: sending failure event (#{state}) for #{key}"
                Flapjack::Data::Event.push('events', failure.merge('time' => Time.now.to_i))
                stop_cond.wait(opts[:interval])
              end
            end
            break if fin
          end
        end

        stopper = Thread.new do
          sleep stop_after
          lock.synchronize do
            puts "#{Time.now}: stopping"
            if recover
              puts "#{Time.now}: sending recovery event for #{key}"
              Flapjack::Data::Event.push('events', recovery.merge('time' => Time.now.to_i))
            end
            @finish = true
            stop_cond.signal
          end
        end

        stopper.join
        failer.join

        Flapjack.redis.quit
      end

    end
  end
end

desc 'Simulates a check by creating a stream of events for Flapjack to process'
command :simulate do |simulate|

  simulate.desc 'Generate a stream of failure events'
  simulate.command :fail do |_fail|
    # Because `fail` is a keyword (that you can actually override in a block,
    # but we want to be good Ruby citizens).

    _fail.flag [:t, 'time'],     :desc => "MINUTES to generate failure events for (0.75)",
      :default_value => 0.75

    _fail.flag [:i, 'interval'], :desc => "SECONDS between events, can be decimal eg 0.1 (10)",
      :default_value => 10

    _fail.flag [:k, 'check'],    :desc => "CHECK to generate failure events for ('HTTP')",
      :default_value => 'HTTP'

    _fail.flag [:s, 'state'],    :desc => "STATE to generate failure events with ('critical')",
      :default_value => 'critical'

    _fail.flag [:T, 'tags'],    :desc => "optional comma-separated list of TAGS to include as part of the event",
      :type => Array, :default_value => []

    _fail.action do |global_options,options,args|
      simulate = Flapjack::CLI::Simulate.new(global_options, options)
      simulate._fail
    end
  end

  simulate.desc 'Generate a stream of failure events, and one final recovery'
  simulate.command :fail_and_recover do |fail_and_recover|

    fail_and_recover.flag [:t, 'time'],     :desc => "MINUTES to generate failure events for (0.75)",
      :default_value => 0.75

    fail_and_recover.flag [:i, 'interval'], :desc => "SECONDS between events, can be decimal eg 0.1 (10)",
      :default_value => 10

    fail_and_recover.flag [:k, 'check'],    :desc => "CHECK to generate failure events for ('HTTP')",
      :default_value => 'HTTP'

    fail_and_recover.flag [:s, 'state'],    :desc => "STATE to generate failure events with ('critical')",
      :default_value => 'critical'

    fail_and_recover.flag [:T, 'tags'],     :desc => "optional comma-separated list of TAGS to include as part of the event",
      :type => Array, :default_value => []

    fail_and_recover.action do |global_options,options,args|
      simulate = Flapjack::CLI::Simulate.new(global_options, options)
      simulate.fail_and_recover
    end
  end

  simulate.desc 'Generate a stream of ok events'
  simulate.command :ok do |ok|

    ok.flag [:t, 'time'],     :desc => "MINUTES to generate ok events for (0.75)",
      :default_value => 0.75

    ok.flag [:i, 'interval'], :desc => "SECONDS between events, can be decimal eg 0.1 (10)",
      :default_value => 10

    ok.flag [:k, 'check'],    :desc => "CHECK to generate ok events for ('HTTP')",
      :default_value => 'HTTP'

    ok.flag [:T, 'tags'],     :desc => "optional comma-separated list of TAGS to include as part of the event",
      :type => Array, :default_value => []

    ok.action do |global_options,options,args|
      simulate = Flapjack::CLI::Simulate.new(global_options, options)
      simulate.ok
    end
  end

end
