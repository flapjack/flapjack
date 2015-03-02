#!/usr/bin/env ruby

require 'hiredis'
require 'flapjack/configuration'

require 'flapjack/data/migration'

module Flapjack
  module CLI
    class Purge

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
          exit_now! "No config data for environment '#{FLAPJACK_ENV}' found in '#{global_options[:config]}'"
        end

        @redis_options = config.for_redis
      end

      def check_history
        # find all checks, or the check given
        # purge old data for check
        options = {}
        if @options[:days]
          options[:older_than] = @options[:days].to_i * 24 * 60 * 60
          raise "days must be resolveable to an integer" unless @options[:days].to_i.to_s == @options[:days]
        end
        checks = if @options[:check]
          [Flapjack::Data::EntityCheck.for_event_id(@options[:check], :redis => redis, :create_entity => true)]
        else
          Flapjack::Data::EntityCheck.all(:redis => redis, :create_entity => true)
        end
        purged = checks.inject([]) do |memo, check|
          pu = check.purge_history(options)
          memo << pu unless pu == 0
          memo
        end

        if purged.empty?
          puts "Nothing to do"
        else
          puts "Purged #{purged.reduce(:+) || 0} historical check states over #{purged.length} checks."
        end
      end

      private

      def redis
        return @redis unless @redis.nil?
        @redis = Redis.new(@redis_options.merge(:driver => :hiredis))
        Flapjack::Data::Migration.migrate_entity_check_data_if_required(:redis => @redis)
        Flapjack::Data::Migration.clear_orphaned_entity_ids(:redis => @redis)
        @redis
      end

    end
  end
end

desc "Purge data from Flapjack's database"
command :purge do |purge|

  purge.desc 'Purge check history'
  purge.command :check_history do |check_history|

    check_history.flag [:d, 'days'], :desc => "purge check history older than DAYS days ago",
      :default_value => 90

    check_history.flag [:c, 'check'], :desc => "affect history of only the CHECK"

    check_history.action do |global_options,options,args|
      purge = Flapjack::CLI::Purge.new(global_options, options)
      purge.check_history
    end
  end

end
