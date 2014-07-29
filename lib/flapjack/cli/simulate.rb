#!/usr/bin/env ruby

require 'eventmachine'
require 'em-synchrony'
require 'redis'
require 'redis/connection/synchrony'

require 'flapjack/configuration'
require 'flapjack/data/event'

module Flapjack
  module CLI
    class Simulate

      def initialize(global_options, options)
        @global_options = global_options
        @options = options

        config = Flapjack::Configuration.new
        config.load(global_options[:config])
        @config_env = config.all

        if @config_env.nil? || @config_env.empty?
          puts "No config data for environment '#{FLAPJACK_ENV}' found in '#{global_options[:config]}'"
          exit 1
        end

        @redis_options = config.for_redis
      end

      def _fail
        events(:state => @options[:state], :recover => false,
          :entity => @options[:entity], :check => @options[:check],
          :tags => @options[:tags],
          :minutes => @options[:time].to_f, :interval => @options[:interval].to_f)
      end

      def fail_and_recover
        events(:state => @options[:state], :recover => true,
          :entity => @options[:entity], :check => @options[:check],
          :tags => @options[:tags],
          :minutes => @options[:time].to_f, :interval => @options[:interval].to_f)
      end

      def ok
        events(:state => 'ok', :recover => false,
          :entity => @options[:entity], :check => @options[:check],
          :tags => @options[:tags],
          :minutes => @options[:time].to_f, :interval => @options[:interval].to_f)
      end

      private

      def redis
        @redis ||= Redis.new(@redis_options)
      end

      def events(opts = {})
        stop_after = (opts[:minutes] * 60).to_i
        recover = opts[:recover]
        state = opts[:state] || 'critical'
        event = {
          'entity' => opts[:entity] || 'foo-app-01',
          'check'  => opts[:check]  || 'HTTP',
          'tags'   => opts[:tags]   || [],
          'type'   => 'service'
        }
        failure  = event.merge('state' => state, 'summary' => 'Simulated check output (test by operator)')
        recovery = event.merge('state' => 'ok',  'summary' => 'Simulated check output (test by operator)')
        key = "#{event['entity']}:#{event['check']}"

        EM.synchrony do

          puts "#{Time.now}: sending failure event (#{state}) for #{key}"
          Flapjack::Data::Event.add(failure, :redis => redis)

          EM.add_timer(stop_after) do
            puts "#{Time.now}: stopping"
            if recover
              EM.synchrony do
                puts "#{Time.now}: sending recovery event for #{key}"
                Flapjack::Data::Event.add(recovery.merge('time' => Time.now.to_i),
                  :redis => redis)
              end
            end
            EM.stop
          end

          EM.add_periodic_timer(opts[:interval]) do
            EM.synchrony do
              puts "#{Time.now}: sending failure event (#{state}) for #{key}"
              Flapjack::Data::Event.add(failure.merge('time' => Time.now.to_i),
                :redis => redis)
            end
          end

        end
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

    _fail.flag [:e, 'entity'],   :desc => "ENTITY to generate failure events for ('foo-app-01')",
      :default_value => 'foo-app-01'

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

    fail_and_recover.flag [:e, 'entity'],   :desc => "ENTITY to generate failure events for ('foo-app-01')",
      :default_value => 'foo-app-01'

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

    ok.flag [:e, 'entity'],   :desc => "ENTITY to generate ok events for ('foo-app-01')",
      :default_value => 'foo-app-01'

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
