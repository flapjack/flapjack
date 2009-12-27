#!/usr/bin/env ruby

require 'net/http'
require 'yajl/json_gem'

module Flapjack
  module Persistence
    class Couch

      attr_accessor :config

      def initialize(options={})
        @options = options
        @config = OpenStruct.new(options)
        @log = @config.log
        
        Flapjack::Persistence::Couch::Connection.setup(@options)
      end

      def any_parents_failed?(id)
        id == "1" ? false : true
      end

      def save_check(attrs)
        true
      end

      def get_check(id)
        id == "4" ? nil : true
      end

      def delete_check(id)
        true
      end

      def all_checks
        [true, true, true]
      end

      def save_check_relationship(attrs)
        true
      end

      def create_event(result)
        true
      end

      def all_events_for(id)
        [true, true, true]
      end

      def all_events
        [true, true, true]
      end

      def all_check_relationships
        [true, true, true]
      end

    end # class Couch
  end # module Persistence
end # module Flapjack

