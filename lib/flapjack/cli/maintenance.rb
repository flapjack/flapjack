#!/usr/bin/env ruby

require 'eventmachine'
require 'em-synchrony'
require 'redis'
require 'redis/connection/synchrony'

require 'flapjack/configuration'
require 'flapjack/data/event'
require 'flapjack/data/entity_check'
require 'terminal-table'

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
      end

      def show
        exit_now!("state must be one of 'ok', 'warning', 'critical', 'unknown'") unless @options[:state].nil? || %w(ok warning critical unknown).include?(@options[:state].downcase)
        exit_now!("type must be one of 'scheduled', 'unscheduled'") unless %w(scheduled unscheduled).include?(@options[:type].downcase)
        %w(started finishing).each do |time|
          exit_now!("#{time.capitalize} time must start with 'more than', 'less than', 'on', 'before', 'after' or between") if @options[time] && !@options[time].downcase.start_with?('more than', 'less than', 'on', 'before', 'after', 'between')
        end
        @options[:finishing] ||= 'after now'
        maintenances = Flapjack::Data::EntityCheck.find_maintenance(@options)
        rows = []
        maintenances.each do |m|
          row = []
          # Convert the unix timestamps of the start and end time back into readable times
          m.each { |k, v| row.push(k.to_s.end_with?('time') ? Time.at(v) : v) }
          rows.push(row)
        end
        puts Terminal::Table.new :headings => ['Entity', 'Check', 'State', 'Start', 'Duration (s)', 'Reason', 'End'], :rows => rows
        maintenances
      end

      def delete
        maintenances = show
        exit_now!('The following maintenances would be deleted.  Run this command again with --apply true to remove them.') unless @options[:apply]
        errors = Flapjack::Data::EntityCheck.delete_maintenance(@options)
        (errors.each { |k, v| puts "#{k}: #{v}" }; exit_now!('Failed to delete maintenances')) if errors.length > 0
        puts "The maintenances above have been deleted"
      end

      def create
        exit_now!("Entity & check must be supplied to create a maintenance period") if @options[:entity].nil? || @options[:check].nil?
        @options[:entity].each do |entity|
          # Create the entity if it doesn't exist, so we can schedule maintenance against it
          Flapjack::Data::Entity.find_by_name(entity, :redis => @redis, :create => true)
          @options[:check].each do |check|
            ec = Flapjack::Data::EntityCheck.for_entity_name(entity, check, :redis => @redis)
            abort('Failed to create scheduled maintenance') unless ec.create_scheduled_maintenance(@options[:started], @options[:duration], :summary => @options[:reason]) if @options[:type] == 'scheduled'
            abort('Failed to create unscheduled maintenance') unless ec.create_unscheduled_maintenance(@options[:started], @options[:duration], :summary => @options[:reason]) if @options[:type] == 'unscheduled'
            puts "Maintenance for #{check} on #{entity} has been created"
          end
        end
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

    show.flag [:e, 'entity'],
      :desc => 'The entity for the maintenance window to occur on.  This can be a string, or a ruby regex of the form \'db*\' or \'[[:lower:]]\''

    show.flag [:c, 'check'],
      :desc => 'The check for the maintenance window to occur on.  This can be a string, or a ruby regex of the form \'http*\' or \'[[:lower:]]\''

    show.flag [:r, 'reason'],
      :desc => 'The reason for the maintenance window to occur.  This can be a string, or a ruby regex of the form \'Downtime for *\' or \'[[:lower:]]\''

    show.flag [:s, 'start', 'started', 'starting'],
      :desc => 'The start time for the maintenance window. This should be prefixed with "more than", "less than", "on", "before", or "after", or of the form "between times and time"'

    show.flag [:d, 'duration'],
      :desc => 'The total duration of the maintenance window. This should be prefixed with "more than", "less than", or "equal to", or or of the form "between 3 and 4 hours".  This should be an interval'

    show.flag [:f, 'finish', 'finished', 'finishing', 'remain', 'remained', 'remaining', 'end'],
      :desc => 'The finishing time for the maintenance window. This should be prefixed with "more than", "less than", "on", "before", or "after", or of the form "between time and time"'

    show.flag [:st, 'state'],
      :desc => 'The state that the check is currently in'

    show.flag [:t, 'type'],
      :desc => 'The type of maintenance scheduled',
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

    delete.flag [:e, 'entity'],
      :desc => 'The entity for the maintenance window to occur on.  This can be a string, or a ruby regex of the form \'db*\' or \'[[:lower:]]\''

    delete.flag [:c, 'check'],
      :desc => 'The check for the maintenance window to occur on.  This can be a string, or a ruby regex of the form \'http*\' or \'[[:lower:]]\''

    delete.flag [:r, 'reason'],
      :desc => 'The reason for the maintenance window to occur.  This can be a string, or a ruby regex of the form \'Downtime for *\' or \'[[:lower:]]\''

    delete.flag [:s, 'start', 'started', 'starting'],
      :desc => 'The start time for the maintenance window. This should be prefixed with "more than", "less than", "on", "before", or "after", or of the form "between times and time"'

    delete.flag [:d, 'duration'],
      :desc => 'The total duration of the maintenance window. This should be prefixed with "more than", "less than", or "equal to", or or of the form "between 3 and 4 hours".  This should be an interval'

    delete.flag [:f, 'finish', 'finished', 'finishing', 'remain', 'remained', 'remaining', 'end'],
      :desc => 'The finishing time for the maintenance window. This should be prefixed with "more than", "less than", "on", "before", or "after", or of the form "between time and time"'

    delete.flag [:st, 'state'],
      :desc => 'The state that the check is currently in'

    delete.flag [:t, 'type'],
      :desc => 'The type of maintenance scheduled',
      :default_value => 'scheduled'

    delete.action do |global_options,options,args|
      maintenance = Flapjack::CLI::Maintenance.new(global_options, options)
      maintenance.delete
    end
  end

  maintenance.desc 'Create a maintenance window'
  maintenance.command :create do |create|

    create.flag [:e, 'entity'],
      :desc => 'The entity for the maintenance window to occur on.  This can be a comma separated list',
      :type => Array

    create.flag [:c, 'check'],
      :desc => 'The check for the maintenance window to occur on.  This can be a comma separated list',
      :type => Array

    create.flag [:r, 'reason'],
      :desc => 'The reason for the maintenance window to occur'

    create.flag [:s, 'start', 'started', 'starting'],
      :desc => 'The start time for the maintenance window'

    create.flag [:d, 'duration'],
      :desc => 'The total duration of the maintenance window.  This should be an interval'

    create.flag [:t, 'type'],
      :desc => 'The type of maintenance scheduled ("scheduled")',
      :default_value => 'scheduled'

    create.action do |global_options,options,args|
      maintenance = Flapjack::CLI::Maintenance.new(global_options, options)
      maintenance.create
    end
  end
end
