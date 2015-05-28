#!/usr/bin/env ruby

require 'hiredis'
require 'flapjack/configuration'

require 'flapjack/data/migration'

module Flapjack
  module CLI
    class Data

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

      def list_entities
        puts CSV.generate(:headers => :first_row, :write_headers => true, :row_sep => "\r\n") {|csv|
          csv << ['id', 'name']
          Flapjack::Data::Entity.all(:redis => redis).each do |entity|
            csv << [entity.id, entity.name]
          end
        }
      end

      def list_orphaned_entities
        orph = orphaned_entity_names

        puts CSV.generate(:headers => :first_row, :write_headers => true, :row_sep => "\r\n") {|csv|
          csv << ['name']
          orph.each {|orp| csv << [orp]}
        }
      end

      def merge_entities_by_id
        source_entity_id = @options[:source]
        dest_entity_id = @options[:destination]

        [source_entity_name, dest_entity_name] = [source_entity_id, source_entity_id].collect do |e_id|
          entity = Flapjack::Data::Entity.find_by_id(e_id, :redis => redis)
          raise "No entity found with id #{en}" if entity.nil?
          entity.name
        end

        Flapjack::Data::Entity.merge(source_entity_name, dest_entity_name, :redis => redis)

        puts "Merged all data from " \
             "#{source_entity_name} (id: #{source_entity_id}) to " \
             "#{dest_entity_name} (id: #{dest_entity_id})."
      end

      def merge_entities_by_name
        source_entity_name = @options[:source]
        dest_entity_name = @options[:destination]

        [source_entity_name, dest_entity_name].each do |en|
          entity = Flapjack::Data::Entity.find_by_name(en, :redis => redis)
          raise "No entity found with name #{en}" if entity.nil?
        end

        Flapjack::Data::Entity.merge(source_entity_name, dest_entity_name, :redis => redis)

        puts "Merged all data from #{source_entity_name} to #{dest_entity_name}."
      end

      private

      def redis
        return @redis unless @redis.nil?
        @redis = Redis.new(@redis_options.merge(:driver => :hiredis))
        Flapjack::Data::Migration.migrate_entity_check_data_if_required(:redis => @redis)
        Flapjack::Data::Migration.clear_orphaned_entity_ids(:redis => @redis)
        @redis
      end

      def orphaned_entity_names
        current_names = Flapjack::Data::Entity.all(:redis => redis).map(&:name)

        all_entity_names = redis.keys("check:*:*").inject([]) do |memo, ck|
          if ck =~ /^check:([^:]+):.+$/
            memo << $1
          end

          memo
        end

        all_entity_names - current_names
      end

    end
  end
end

desc "Operations on Flapjack's Redis data store"
command :data do |data|

  data.desc 'List entities'
  data.command :list_entities do |list_entities|
    list_entities.action do |global_options,options,args|
      data = Flapjack::CLI::Data.new(global_options, options)
      data.list_entities
    end
  end

  data.desc 'List orphaned entity records'
  data.command :list_orphaned_entities do |list_orphaned_entities|
    list_orphaned_entities.action do |global_options,options,args|
      data = Flapjack::CLI::Data.new(global_options, options)
      data.list_orphaned_entities
    end
  end

  data.desc 'Merge two entities (by id)'
  data.command :merge_entities_by_id do |merge_entities_by_id|
    merge_entities_by_id.flag [:s, 'source'], :desc => "", :required => true
    merge_entities_by_id.flag [:d, 'destination'], :desc => "", :required => true

    merge_entities_by_id.action do |global_options,options,args|
      data = Flapjack::CLI::Data.new(global_options, options)
      data.merge_entities_by_id
    end
  end

  data.desc 'Merge two entities (by name)'
  data.command :merge_entities_by_name do |merge_entities_by_name|
    merge_entities_by_name.flag [:s, 'source'], :desc => "", :required => true
    merge_entities_by_name.flag [:d, 'destination'], :desc => "", :required => true

    merge_entities_by_name.action do |global_options,options,args|
      data = Flapjack::CLI::Data.new(global_options, options)
      data.merge_entities_by_name
    end
  end

end
