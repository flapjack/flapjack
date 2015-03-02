#!/usr/bin/env ruby

require 'redis'
require 'hiredis'

require 'flapjack/configuration'
require 'flapjack/data/event'
require 'flapjack/data/entity_check'
require 'flapjack/data/migration'
require 'terminal-table'

module Flapjack
  module CLI
    class Maintenance

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
        errors = Flapjack::Data::EntityCheck.create_maintenance(@options)
        (errors.each { |k, v| puts "#{k}: #{v}" }; exit_now!('Failed to create maintenances')) if errors.length > 0
        puts "The maintenances specified have been created"
      end

      private

      def redis
        return @redis unless @redis.nil?
        @redis = Redis.new(@redis_options.merge(:driver => :hiredis))
        Flapjack::Data::Migration.migrate_entity_check_data_if_required(:redis => @redis)
        Flapjack::Data::Migration.clear_orphaned_entity_ids(:redis => @redis)
        Flapjack::Data::Migration.validate_scheduled_maintenance_periods(:redis => @redis)
        @redis
      end

    end
  end
end

desc 'Show, create and delete maintenance windows'
command :maintenance do |maintenance|


  maintenance.desc 'Show maintenance windows according to criteria (default: all ongoing maintenance)'
  maintenance.command :show do |show|

    show.flag ['entity', :e],
      :desc => 'The entity for the maintenance window to occur on.  This can be a string, or a ruby regex of the form \'db*\' or \'[[:lower:]]\''

    show.flag ['check', :c],
      :desc => 'The check for the maintenance window to occur on.  This can be a string, or a ruby regex of the form \'http*\' or \'[[:lower:]]\''

    show.flag ['reason', :r],
      :desc => 'The reason for the maintenance window to occur.  This can be a string, or a ruby regex of the form \'Downtime for *\' or \'[[:lower:]]\''

    show.flag ['start', 'started', 'starting', :s],
      :desc => 'The start time for the maintenance window, eg \'before 10am\'. This should be prefixed with \'more than\', \'less than\', \'on\', \'before\', or \'after\', or of the form \'between times and time\''

    show.flag ['duration', :d],
      :desc => 'The total duration of the maintenance window, eg \'equal to 5 hours\'. This should be prefixed with \'more than\', \'less than\', \'before, \'after\' or \'equal to\', or or of the form \'between 3 and 4 hours\'.  This should be an interval'

    show.flag ['finish', 'finished', 'finishing', 'remain', 'remained', 'remaining', 'end', :f],
      :desc => 'The finishing time for the maintenance window, eg \'more than 1 year from now\'. This should be prefixed with \'more than\', \'less than\', \'on\', \'before\', or \'after\', or of the form \'between time and time\''

    show.flag ['state', :st],
      :desc => 'The state that the check is currently in'

    show.flag ['type', :t],
      :desc => 'The type of maintenance scheduled',
      :default_value => 'scheduled'

    show.action do |global_options,options,args|
      maintenance = Flapjack::CLI::Maintenance.new(global_options, options)
      maintenance.show
    end
  end

  maintenance.desc 'Delete maintenance windows according to criteria (default: all ongoing maintenance)'
  maintenance.command :delete do |delete|

    delete.flag ['apply', :a],
      :desc => 'Whether this deletion should occur',
      :default_value => false

    delete.flag ['entity', :e],
      :desc => 'The entity for the maintenance window to occur on.  This can be a string, or a ruby regex of the form \'db*\' or \'[[:lower:]]\''

    delete.flag ['check', :c],
      :desc => 'The check for the maintenance window to occur on.  This can be a string, or a ruby regex of the form \'http*\' or \'[[:lower:]]\''

    delete.flag ['reason', :r],
      :desc => 'The reason for the maintenance window to occur.  This can be a string, or a ruby regex of the form \'Downtime for *\' or \'[[:lower:]]\''

    delete.flag ['start', 'started', 'starting', :s],
      :desc => 'The start time for the maintenance window, eg \'before 10am\'. This should be prefixed with \'more than\', \'less than\', \'on\', \'before\', or \'after\', or of the form \'between times and time\''

    delete.flag ['duration', :d],
      :desc => 'The total duration of the maintenance window, eg \'equal to 5 hours\'. This should be prefixed with \'more than\', \'less than\', \'before, \'after\' or \'equal to\', or or of the form \'between 3 and 4 hours\'.  This should be an interval'

    delete.flag ['finish', 'finished', 'finishing', 'remain', 'remained', 'remaining', 'end', :f],
      :desc => 'The finishing time for the maintenance window, eg \'more than 1 year from now\'. This should be prefixed with \'more than\', \'less than\', \'on\', \'before\', or \'after\', or of the form \'between time and time\''

    delete.flag ['state', :st],
      :desc => 'The state that the check is currently in'

    delete.flag ['type', :t],
      :desc => 'The type of maintenance scheduled',
      :default_value => 'scheduled'

    delete.action do |global_options,options,args|
      maintenance = Flapjack::CLI::Maintenance.new(global_options, options)
      maintenance.delete
    end
  end

  maintenance.desc 'Create a maintenance window'
  maintenance.command :create do |create|

    create.flag ['entity', :e],
      :desc => 'The entity for the maintenance window to occur on.  This can be a comma separated list',
      :type => Array,
      :required => true

    create.flag ['check', :c],
      :desc => 'The check for the maintenance window to occur on.  This can be a comma separated list',
      :type => Array,
      :required => true

    create.flag ['reason', :r],
      :desc => 'The reason for the maintenance window to occur',
      :required => true

    create.flag ['start', 'started', 'starting', :s],
      :desc => 'The start time for the maintenance window, eg \'now\' or \'in 3 hours\'',
      :required => true

    create.flag ['duration', :d],
      :desc => 'The total duration of the maintenance window, eg \'30 minutes\'.  This should be an interval',
      :required => true

    create.flag ['type', :t],
      :desc => 'The type of maintenance scheduled (\'scheduled\')',
      :default_value => 'scheduled'

    create.action do |global_options,options,args|
      maintenance = Flapjack::CLI::Maintenance.new(global_options, options)
      maintenance.create
    end
  end
end
