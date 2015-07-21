#!/usr/bin/env ruby

require 'hiredis'
require 'flapjack/configuration'

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
          exit_now! "No config data found in '#{global_options[:config]}'"
        end

        Flapjack::RedisProxy.config = config.for_redis
        Zermelo.redis = Flapjack.redis
      end

      def check_history
        # find all checks, or the check given
        # purge old data for check
        options = {}
        if @options[:days]
          options[:older_than] = @options[:days].to_i * 24 * 60 * 60
          raise "days must be resolvable to an integer" unless @options[:days].to_i.to_s == @options[:days]
        end
        checks = if @options[:check]
          [Flapjack::Data::Check.find_by_id(options[:check])].compact
        else
          Flapjack::Data::Check.all
        end

        purge_before = Time.now - options[:older_than]
        purge_range = Zermelo::Filters::IndexRange.new(nil, purge_before, :by_score => true)

        purged = checks.inject(0) do |memo, check|
          purgees = check.states.intersect(:created_at => purge_range)
          num = purgees.count
          if num > 0
            purgees.destroy_all
            memo += num
          end
          memo
        end

        if purged == 0
          puts "Nothing to do"
        else
          puts "Purged #{purged.reduce(:+) || 0} historical check states over #{purged.length} checks."
        end
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

    check_history.flag [:c, 'check'], :desc => "affect history of only the CHECK with the provided id"

    check_history.action do |global_options,options,args|
      purge = Flapjack::CLI::Purge.new(global_options, options)
      purge.check_history
    end
  end

end
