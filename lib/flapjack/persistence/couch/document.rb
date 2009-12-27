#!/usr/bin/env ruby

module Flapjack
  module Persistence
    class Couch
      class Document
        def initialize(options={})
          if options[:table] && options[:persisted]
            @table = options[:table]
            @persisted = options[:persisted]
          else
            @table = options.dup
          end
        end

        def self.get(id)
          if response = Flapjack::Persistence::Couch::Connection.get(id)
            self.new(:table => response, :persisted => true)
          else
            nil
          end
        end

        def save
          if @persisted
            response = Flapjack::Persistence::Couch::Connection.put(:document => @table)
          else
            response = Flapjack::Persistence::Couch::Connection.post(:document => @table)
          end

          @table["id"]  = response["id"]
          @table["_rev"] = response["rev"]
          @persisted = true

          response["ok"]
        end

        def status=(value)
          @table["status"] = value
        end

        def id
          @table["id"]
        end

        def [](id)
          @table[id]
        end
        
        def []=(id, value)
          @table[id] = value
        end

        def reload
          @table = Flapjack::Persistence::Couch.get(id)
        end

      end # class Document
    end # class Couch
  end # module Persistence
end # module Flapjack
