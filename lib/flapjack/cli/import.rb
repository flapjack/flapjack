#!/usr/bin/env ruby

require 'redis'

require 'flapjack/configuration'
require 'flapjack/data/contact'
require 'flapjack/data/entity'
require 'flapjack/data/migration'

module Flapjack
  module CLI
    class Import

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

      # TODO should these be similar to JSONAPI structures? e.g.
      # {'contacts' => [CONTACT_HASH, ...]}

      def contacts
        conts = Flapjack.load_json(File.new(@options[:from]))

        if conts && conts.is_a?(Enumerable) && conts.any? {|e| !e['id'].nil?}
          conts.each do |contact|
            unless contact['id']
              puts "Contact not imported as it has no id: " + contact.inspect
              next
            end
            Flapjack::Data::Contact.add(contact, :redis => redis)
          end
        end

      end

      def entities
        ents = Flapjack.load_json(File.new(@options[:from]))

        if ents && ents.is_a?(Enumerable) && ents.any? {|e| !e['id'].nil?}
          ents.each do |entity|
            unless entity['id']
              puts "Entity not imported as it has no id: " + entity.inspect
              next
            end
            Flapjack::Data::Entity.add(entity, :redis => redis)
          end
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

desc 'Bulk import data from an external source, reading from JSON formatted data files'
command :import do |import|

  import.desc 'Import contacts'
  import.command :contacts do |contacts|

    contacts.flag [:f, 'from'],     :desc => 'PATH of the contacts JSON file to import',
      :required => true

    contacts.action do |global_options,options,args|
      import = Flapjack::CLI::Import.new(global_options, options)
      import.contacts
    end
  end

  import.desc 'Import entities'
  import.command :entities do |entities|

    entities.flag [:f, 'from'],     :desc => 'PATH of the entities JSON file to import',
      :required => true

    entities.action do |global_options,options,args|
      import = Flapjack::CLI::Import.new(global_options, options)
      import.entities
    end
  end

end
