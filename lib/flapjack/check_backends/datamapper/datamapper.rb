#!/usr/bin/env ruby 

require 'dm-core'
require 'dm-validations'
require 'dm-types'
require 'dm-timestamps'

Dir.glob(File.join(File.dirname(__FILE__), 'models', '*.rb')).each do |model|
  require model
end

module Flapjack
  module CheckBackends
    class Datamapper
      def initialize(options={})
        @options = options
        @config = OpenStruct.new(options)
        @log = @config.log
        connect
      end

      def any_parents_failed?(result)
        check = Check.get(result.id)
        check.worst_parent_status != 0
      end

      def save(result)
        check = Check.get(result.id)
        check.status = result.status
        check.save
      end

      def create_event(result)
        event = Event.new(:check_id => result.id)
        event.save
      end

      private 
      def connect
        raise ArgumentError, "Database URI wasn't specified" unless @config.uri
        DataMapper.setup(:default, @config.uri)
        validate
      end

      def validate
        begin
          DataMapper.repository(:default).adapter.execute("SELECT 'id' FROM 'checks';")
        rescue Sqlite3Error => e
          @log.warning("The specified database doesn't appear to have any structure!")
          @log.warning("Exiting.")
          raise
        end
      end
    end
  end
end

