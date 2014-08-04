#!/usr/bin/env ruby

require 'eventmachine'
require 'em-synchrony'
require 'redis'
require 'redis/connection/synchrony'

require 'flapjack/configuration'
require 'flapjack/data/event'
require 'flapjack/data/entity_check'
require 'terminal-table'
require 'pp'
require 'pry'

module Flapjack
  module CLI
    class Maintenance

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

        @redis_options = config.for_redis.merge(:driver => :ruby)
        @options[:redis] = redis

        @options['reason'] = @options['reason'].to_s unless @options['reason'].nil? || @options['reason'].is_a?(String)
        exit_now!("state must be one of 'ok', 'warning', 'critical', 'unknown'") unless %w(ok warning critical unknown).include?(@options['state'].downcase)
        exit_now!("type must be one of 'scheduled', 'unscheduled'") unless %w(scheduled unscheduled).include?(@options['type'].downcase)
        %w(started finishing).each do |time|
          exit_now!("#{time.upcase} time must start with 'more than', 'less than', 'on', 'before', 'after' or between") if @options[time] && !@options[time].downcase.start_with?('more than', 'less than', 'on', 'before', 'after', 'between')
        end
        @options['finishing'] ||= 'after now'
      end

      def show
        maintenances = Flapjack::Data::EntityCheck.find_maintenance(@options)
        rows = []
        maintenances.each do |m|
          row = []
          # Convert the unix timestamps of the start and end time back into readable times
          m.each { |k, v| row.push(k.to_s.end_with?('time') ? Time.at(v) : v) }
          rows.push(row)
        end
        puts Terminal::Table.new :headings => ['Name', 'State', 'Start', 'Duration (s)', 'Reason', 'End'], :rows => rows
        maintenances
      end

      def delete
        maintenances = show
        exit_now!('The following maintenances would be deleted.  Run this command again with --apply true to remove them.') unless @options['apply']
        exit_now!('Failed to delete maintenances') unless Flapjack::Data::EntityCheck.delete_maintenance(@options)
      end

      private

      def redis
        @redis ||= Redis.new(@redis_options)
      end

    end
  end
end

desc 'Show, create and delete maintenance windows'
command :maintenance do |maintenance|


  maintenance.desc 'Show maintenance windows according to criteria (default: all ongoing maintenance)'
  maintenance.command :show do |show|

    show.flag [:r, 'reason'],
      :desc => 'The reason for the maintenance window to occur.  This can be a ruby regex of the form \'Downtime for *\' or \'[[:lower:]]\''

    show.flag [:s, 'started'],
      :desc => 'The start time for the maintenance window. This should be prefixed with "more than", "less than", "on", "before", or "after", or of the form "between times and time"'

    show.flag [:d, 'duration'],
      :desc => 'The total duration of the maintenance window. This should be prefixed with "more than", "less than", or "equal to", or or of the form "between 3 and 4 hours".  This should be an interval'

    show.flag [:e, 'finishing', 'remaining'],
      :desc => 'The finishing time for the maintenance window. This should be prefixed with "more than", "less than", "on", "before", or "after", or of the form "between time and time"'

    show.flag [:st, 'state'],
      :desc => 'STATE that alerts are in ("critical")',
      :default_value => 'critical'

    show.flag [:t, 'type'],
      :desc => 'TYPE of maintenance scheduled ("scheduled")',
      :default_value => 'scheduled'

    show.action do |global_options,options,args|
      maintenance = Flapjack::CLI::Maintenance.new(global_options, options)
      maintenance.show
    end
  end

  maintenance.desc 'Delete maintenance windows according to criteria (default: all ongoing maintenance)'
  maintenance.command :delete do |delete|

    delete.flag [:a, 'apply'],
      :desc => 'Whether this deletion should occur',
      :default_value => false

    delete.flag [:r, 'reason'],
      :desc => 'The reason for the maintenance window to occur.  This can be a ruby regex of the form \'Downtime for *\' or \'[[:lower:]]\''

    delete.flag [:s, 'started'],
      :desc => 'The start time for the maintenance window. This should be prefixed with "more than", "less than", "on", "before", or "after", or of the form "between times and time"'

    delete.flag [:d, 'duration'],
      :desc => 'The total duration of the maintenance window. This should be prefixed with "more than", "less than", or "equal to", or or of the form "between 3 and 4 hours".  This should be an interval'

    delete.flag [:e, 'finishing', 'remaining'],
      :desc => 'The finishing time for the maintenance window. This should be prefixed with "more than", "less than", "on", "before", or "after", or of the form "between time and time"'

    delete.flag [:st, 'state'],
      :desc => 'STATE that alerts are in ("critical")',
      :default_value => 'critical'

    delete.flag [:t, 'type'],
      :desc => 'TYPE of maintenance scheduled ("scheduled")',
      :default_value => 'scheduled'

    delete.action do |global_options,options,args|
      maintenance = Flapjack::CLI::Maintenance.new(global_options, options)
      maintenance.delete
    end
  end
end